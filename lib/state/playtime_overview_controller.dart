import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/play_session.dart';
import '../models/steam_playtime.dart';
import '../models/playtime_reconciliation.dart';
import '../services/playtime_reconciliation_service.dart';
import '../services/steam_local_playtime.dart';
import '../services/steam_playtime_service.dart';
import '../services/steam_playtime_store.dart';

/// UI state only. Sessions remain owned by SessionTracker; no synthetic sessions.
class PlaytimeOverviewController extends ChangeNotifier {
  PlaytimeOverviewController(this.steam)
    : reconciliation = PlaytimeReconciliationService(
        steam,
        now: steam.provider.now,
      );
  final SteamPlaytimeService steam;
  final PlaytimeReconciliationService reconciliation;
  SteamPlaytimeData data = SteamPlaytimeData();
  SteamAccountDetection? detection;
  bool busy = false, refreshing = false;
  String? message;
  Future<void>? _loading, _queuedRefresh;
  bool _activeForcedRefresh = false;
  DateTime? _lastCacheCheck;
  String? _cacheAccount;
  Set<int> _coveredIds = {};
  Map<int, SteamPlaytimeSnapshot> automaticSnapshots = {};
  SteamPlaytimeSnapshot? snapshotFor(int id) {
    final active = detection?.proposal?.account;
    if (active == null || (data.confirmedAccount != null && !accountMatches)) {
      return null;
    }
    return automaticSnapshots[id]?.account.steamId64 == active.steamId64
        ? automaticSnapshots[id]
        : data.latest['${active.steamId64}:$id'];
  }

  /// Never persisted or used by Activity. Full overlap is an explicit UI assumption.
  ({int combined, int historical, int overlap})? provisional(
    int id,
    Iterable<PlaySession> sessions,
  ) {
    final account = detection?.proposal?.account;
    if (account == null ||
        data.recoveredFromBackup ||
        checkedAt == null ||
        steam.provider.now().isBefore(checkedAt!) ||
        steam.provider.now().difference(checkedAt!) >
            const Duration(minutes: 2) ||
        (data.confirmedAccount != null && !accountMatches) ||
        (data.baselines['${account.steamId64}:$id']?.isNotEmpty ?? false)) {
      return null;
    }
    final snapshot = snapshotFor(id);
    if (snapshot?.lifetimeMinutes == null ||
        snapshot!.staleAt(steam.provider.now(), steam.provider.maxCacheAge)) {
      return null;
    }
    try {
      final tracked = TrackedPlaytimeCheckpoint.capture(id, sessions);
      final lifetime = snapshot.lifetimeMinutes! * 60;
      if (lifetime < tracked.total) {
        return null; // Don't clamp uncertain overlap.
      }
      return (
        combined: lifetime - tracked.total + tracked.active,
        historical: lifetime - tracked.total,
        overlap: tracked.total,
      );
    } on PlaytimeReconciliationFailure {
      return null;
    }
  }

  bool _disposed = false;
  bool _closing = false;
  DateTime? checkedAt;
  DateTime? refreshedAt;

  bool get accountMatches =>
      data.confirmedAccount != null &&
      detection?.proposal?.account.steamId64 ==
          data.confirmedAccount!.steamId64;

  Future<void> load(
    Iterable<int> ids, {
    bool refresh = false,
    bool automatic = false,
  }) {
    if (_closing) return Future.value();
    final requested = ids.toSet();
    final pending = _loading;
    if (pending != null) {
      // A burst of manual refreshes behind an identity read gets ONE follow-up.
      if (refresh && !automatic && !_activeForcedRefresh) {
        return _queuedRefresh ??= pending
            .then((_) => load(requested, refresh: true))
            .whenComplete(() => _queuedRefresh = null);
      }
      return pending;
    }
    if (automatic &&
        checkedAt != null &&
        steam.provider.now().difference(checkedAt!) <
            const Duration(seconds: 5) &&
        !steam.provider.now().isBefore(checkedAt!) &&
        _coveredIds.containsAll(requested)) {
      return Future.value();
    }
    _activeForcedRefresh = refresh && !automatic;
    return _loading = _load(requested, refresh, automatic).whenComplete(() {
      _loading = null;
      _activeForcedRefresh = false;
    });
  }

  String _signature() => jsonEncode([
    data.toJson(),
    detection?.proposal?.account.steamId64,
    message,
    automaticSnapshots.values.map((s) => s.toJson()).toList(),
  ]);

  Future<void> _load(Set<int> ids, bool refresh, bool automatic) async {
    final before = _signature();
    final previouslyExpired =
        checkedAt == null ||
        steam.provider.now().difference(checkedAt!) >
            const Duration(minutes: 2);
    busy = true;
    message = null;
    if (!automatic) _notify();
    try {
      data = await steam.store.load();
      detection = await steam.proposeAccount();
      final account = detection?.proposal?.account;
      if (_cacheAccount != account?.steamId64) automaticSnapshots = {};
      final shouldRead =
          refresh &&
          account != null &&
          !data.recoveredFromBackup &&
          (data.confirmedAccount == null || accountMatches) &&
          (!automatic ||
              _lastCacheCheck == null ||
              _cacheAccount != account.steamId64 ||
              !_coveredIds.containsAll(ids) ||
              steam.provider.now().difference(_lastCacheCheck!) >=
                  const Duration(minutes: 5));
      if (shouldRead) {
        refreshing = true;
        if (!automatic) _notify();
        final proposal = detection!.proposal!;
        final result = data.confirmedAccount == null
            ? await steam.provider.read(proposal, ids)
            : await steam.refresh(ids);
        _lastCacheCheck = steam.provider.now();
        _cacheAccount = account.steamId64;
        _coveredIds = ids;
        refreshedAt = _lastCacheCheck;
        automaticSnapshots = {for (final s in result.snapshots) s.appId: s};
        if (result.problem != null) {
          message =
              'Steam cache could not be fully verified. Check Steam and try Refresh again.';
        }
        if (data.confirmedAccount != null) data = await steam.store.load();
        detection = await steam.proposeAccount();
        if (detection?.proposal?.account.steamId64 != _cacheAccount) {
          automaticSnapshots = {};
        }
      }
      checkedAt = steam.provider.now();
    } catch (_) {
      detection = null;
      automaticSnapshots = {};
      message =
          'Steam playtime storage or account could not be read. Existing data was preserved.';
    } finally {
      busy = false;
      refreshing = false;
      if (!automatic || previouslyExpired || before != _signature()) _notify();
    }
  }

  Future<void> confirm(SteamAccountProposal proposal, Iterable<int> ids) async {
    await steam.confirmAccount(proposal);
    await load(ids, refresh: true);
  }

  CombinedPlaytimeResult estimate(int id, Iterable<PlaySession> sessions) {
    TrackedPlaytimeCheckpoint current;
    try {
      current = TrackedPlaytimeCheckpoint.capture(id, sessions);
    } on PlaytimeReconciliationFailure catch (e) {
      return CombinedPlaytimeResult(
        measuredActiveSeconds: 0,
        issues: {e.issue},
      );
    }
    PlaytimeReconciliationIssue? blocked;
    if (data.recoveredFromBackup) {
      blocked = PlaytimeReconciliationIssue.sidecarRecoveryRequired;
    } else if (data.confirmedAccount == null) {
      blocked = PlaytimeReconciliationIssue.accountNotConfirmed;
    } else if (detection?.proposal == null ||
        checkedAt == null ||
        steam.provider.now().difference(checkedAt!) >
            const Duration(minutes: 2)) {
      blocked = PlaytimeReconciliationIssue.accountUnavailable;
    } else if (!accountMatches) {
      blocked = PlaytimeReconciliationIssue.accountChanged;
    }
    if (blocked != null) {
      return CombinedPlaytimeResult(
        measuredActiveSeconds: current.active,
        issues: {blocked},
      );
    }
    final key = '${data.confirmedAccount!.steamId64}:$id';
    final history = data.baselines[key];
    return reconcilePlaytime(
      baseline: history == null || history.isEmpty ? null : history.last,
      confirmedAccount: data.confirmedAccount,
      current: current,
      now: steam.provider.now(),
      latestSteam: data.latest[key],
      maxSnapshotAge: steam.provider.maxCacheAge,
    );
  }

  void _notify() {
    if (!_disposed && !_closing) notifyListeners();
  }

  Future<void> close() async {
    _closing = true;
    // Drain reads before releasing the profile or deleting a disposable vault.
    // A queued follow-up sees _closing and cannot start another cache job.
    await _queuedRefresh;
    await _loading;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
