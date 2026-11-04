import 'dart:convert';
import '../models/play_session.dart';
import '../models/playtime_reconciliation.dart';
import '../models/steam_playtime.dart';
import 'steam_playtime_service.dart';
import 'steam_playtime_store.dart';

/// Frozen preview. Acceptance rechecks the exact snapshots, session checkpoint,
/// account and revision. Nothing is accepted by a Steam refresh or calculation.
class PlaytimeBaselineProposal {
  const PlaytimeBaselineProposal._(this.draft, this.expectedRevision);
  final PlaytimeBaseline draft;
  final int expectedRevision;
}

class PlaytimeReconciliationService {
  PlaytimeReconciliationService(this.steam, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final SteamPlaytimeService steam;
  final DateTime Function() now;

  Future<SteamPlaytimeAccount> _requireActiveAccount(
    SteamPlaytimeData data,
  ) async {
    if (data.recoveredFromBackup) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.sidecarRecoveryRequired,
      );
    }
    final account = data.confirmedAccount;
    if (account == null) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.accountNotConfirmed,
      );
    }
    final active = await steam.proposeAccount();
    if (active.proposal == null) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.accountUnavailable,
      );
    }
    if (active.proposal!.account.steamId64 != account.steamId64) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.accountChanged,
      );
    }
    return account;
  }

  /// For existing tracked runtime, a numeric overlap and an explicit evidence
  /// choice are mandatory. There is no automatic assume-all-overlap option.
  Future<PlaytimeBaselineProposal> proposeSteam(
    int appId,
    Iterable<PlaySession> sessions, {
    int? overlapSeconds,
    SteamOverlapEvidence evidence = SteamOverlapEvidence.unknown,
    bool allowStaleSnapshot = false,
  }) => _propose(
    appId,
    sessions,
    overlapSeconds: overlapSeconds,
    evidence: evidence,
    allowStaleSnapshot: allowStaleSnapshot,
  );

  /// User enters unmeasured historical runtime directly, not a Steam lifetime
  /// total. Zero explicitly means no historical add-on; missing data stays null.
  Future<PlaytimeBaselineProposal> proposeManualHistorical(
    int appId,
    Iterable<PlaySession> sessions, {
    required int historicalSeconds,
  }) => _propose(appId, sessions, manualHistory: historicalSeconds);

  Future<PlaytimeBaselineProposal> _propose(
    int appId,
    Iterable<PlaySession> sessions, {
    int? manualHistory,
    int? overlapSeconds,
    SteamOverlapEvidence evidence = SteamOverlapEvidence.unknown,
    bool allowStaleSnapshot = false,
  }) async {
    final data = await steam.store.load();
    final account = await _requireActiveAccount(data);
    final tracked = TrackedPlaytimeCheckpoint.capture(appId, sessions);
    if (tracked.hasOpenSession) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.gameRunning,
      );
    }
    final key = '${account.steamId64}:$appId',
        snapshot = data.latest['${account.steamId64}:$appId'];
    final at = now().toUtc();
    final stale = snapshot?.staleAt(at, steam.provider.maxCacheAge) ?? true;
    int historical;
    if (manualHistory != null) {
      if (manualHistory < 0 || manualHistory > 0x1fffffffffffff) {
        throw const PlaytimeReconciliationFailure(
          PlaytimeReconciliationIssue.invalidHistoricalValue,
        );
      }
      historical = manualHistory;
      overlapSeconds = null;
      evidence = SteamOverlapEvidence.notApplicable;
    } else {
      final minutes = snapshot?.lifetimeMinutes;
      if (minutes == null) {
        throw const PlaytimeReconciliationFailure(
          PlaytimeReconciliationIssue.steamUnavailable,
        );
      }
      if (stale && !allowStaleSnapshot) {
        throw const PlaytimeReconciliationFailure(
          PlaytimeReconciliationIssue.staleSteamSnapshot,
        );
      }
      final total = minutes * 60;
      if (overlapSeconds == null && tracked.total == 0) {
        overlapSeconds = 0;
        evidence = SteamOverlapEvidence.noTrackedRuntime;
      } else if (overlapSeconds == null && total == 0) {
        overlapSeconds = 0;
        evidence = SteamOverlapEvidence.zeroSteamLifetime;
      } else if (overlapSeconds == null ||
          ![
            SteamOverlapEvidence.userConfirmed,
            SteamOverlapEvidence.userAssumed,
          ].contains(evidence)) {
        throw const PlaytimeReconciliationFailure(
          PlaytimeReconciliationIssue.overlapRequired,
        );
      }
      if (overlapSeconds < 0 ||
          overlapSeconds > total ||
          overlapSeconds > tracked.total) {
        throw const PlaytimeReconciliationFailure(
          PlaytimeReconciliationIssue.invalidOverlap,
        );
      }
      historical = total - overlapSeconds;
    }
    final revision = data.baselines[key]?.length ?? 0;
    return PlaytimeBaselineProposal._(
      PlaytimeBaseline(
        account: account,
        appId: appId,
        revision: revision + 1,
        capturedAt: at,
        acceptedAt: at,
        source: manualHistory == null
            ? HistoricalPlaytimeSource.steamCache
            : HistoricalPlaytimeSource.manualHistorical,
        tracked: tracked,
        historicalSeconds: historical,
        overlapSeconds: overlapSeconds,
        overlapEvidence: evidence,
        steamSnapshot: snapshot,
        acceptedStaleSnapshot:
            manualHistory == null && stale && allowStaleSnapshot,
      ),
      revision,
    );
  }

  /// Only call in response to an explicit future UI acceptance action. Earlier
  /// revisions remain intact; reaccepting the same preview cannot add hours.
  Future<PlaytimeBaseline> accept(
    PlaytimeBaselineProposal proposal,
    Iterable<PlaySession> currentSessions,
  ) => steam.store.update((data) async {
    final account = await _requireActiveAccount(data);
    final draft = proposal.draft;
    if (account.steamId64 != draft.account.steamId64) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.accountChanged,
      );
    }
    final history = data.baselines[draft.key] ?? const <PlaytimeBaseline>[];
    if (history.length != proposal.expectedRevision) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.proposalExpired,
      );
    }
    final current = TrackedPlaytimeCheckpoint.capture(
      draft.appId,
      currentSessions,
    );
    if (!current.sameHistory(draft.tracked)) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.sessionHistoryChanged,
      );
    }
    final latest = data.latest[draft.key];
    if (jsonEncode(latest?.toJson()) !=
        jsonEncode(draft.steamSnapshot?.toJson())) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.proposalExpired,
      );
    }
    final at = now().toUtc();
    if (at.isBefore(draft.capturedAt)) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.proposalExpired,
      );
    }
    if (draft.source == HistoricalPlaytimeSource.steamCache &&
        draft.steamSnapshot!.staleAt(at, steam.provider.maxCacheAge) &&
        !draft.acceptedStaleSnapshot) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.staleSteamSnapshot,
      );
    }
    final baseline = PlaytimeBaseline(
      account: draft.account,
      appId: draft.appId,
      revision: draft.revision,
      capturedAt: draft.capturedAt,
      acceptedAt: at,
      source: draft.source,
      tracked: draft.tracked,
      historicalSeconds: draft.historicalSeconds,
      overlapSeconds: draft.overlapSeconds,
      overlapEvidence: draft.overlapEvidence,
      steamSnapshot: draft.steamSnapshot,
      acceptedStaleSnapshot: draft.acceptedStaleSnapshot,
    );
    return (
      SteamPlaytimeData(
        confirmedAccount: data.confirmedAccount,
        latest: data.latest,
        lastKnown: data.lastKnown,
        baselines: {
          ...data.baselines,
          draft.key: [...history, baseline],
        },
      ),
      baseline,
    );
  });

  /// A separate projection for the future overview, never VaultController.played.
  Future<CombinedPlaytimeResult> evaluate(
    int appId,
    Iterable<PlaySession> sessions,
  ) async {
    final data = await steam.store.load();
    final tracked = TrackedPlaytimeCheckpoint.capture(appId, sessions);
    try {
      await _requireActiveAccount(data);
    } on PlaytimeReconciliationFailure catch (e) {
      return CombinedPlaytimeResult(
        measuredActiveSeconds: tracked.active,
        issues: {e.issue},
      );
    }
    final key = '${data.confirmedAccount?.steamId64}:$appId';
    final history = data.baselines[key];
    return reconcilePlaytime(
      baseline: history?.last,
      confirmedAccount: data.confirmedAccount,
      current: tracked,
      now: now(),
      latestSteam: data.latest[key],
      maxSnapshotAge: steam.provider.maxCacheAge,
    );
  }
}
