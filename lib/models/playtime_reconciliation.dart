import 'play_session.dart';
import 'steam_playtime.dart';

enum HistoricalPlaytimeSource { steamCache, manualHistorical }

enum SteamOverlapEvidence {
  unknown,
  userConfirmed,
  userAssumed,
  noTrackedRuntime,
  zeroSteamLifetime,
  notApplicable,
}

enum PlaytimeReconciliationIssue {
  accountNotConfirmed,
  accountUnavailable,
  accountChanged,
  steamUnavailable,
  staleSteamSnapshot,
  steamCounterDecreased,
  overlapRequired,
  invalidOverlap,
  invalidHistoricalValue,
  gameRunning,
  invalidSessionData,
  sessionHistoryChanged,
  proposalExpired,
  baselineMissing,
  sidecarRecoveryRequired,
}

class PlaytimeReconciliationFailure implements Exception {
  const PlaytimeReconciliationFailure(this.issue);
  final PlaytimeReconciliationIssue issue;
  @override
  String toString() => 'Playtime reconciliation requires review: ${issue.name}';
}

/// Immutable evidence of counted time, not a replacement or synthetic session.
class SessionPlaytimeCheckpoint {
  SessionPlaytimeCheckpoint(this.id, this.startedAt, this.total, this.active) {
    if (id.isEmpty ||
        total < 0 ||
        total > 0x1fffffffffffff ||
        active < 0 ||
        active > total) {
      throw const FormatException('Invalid session playtime checkpoint');
    }
  }
  final String id;
  final DateTime startedAt;
  final int total, active;
  bool matches(SessionPlaytimeCheckpoint other) =>
      id == other.id &&
      startedAt.isAtSameMomentAs(other.startedAt) &&
      total == other.total &&
      active == other.active;
  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'total': total,
    'active': active,
  };
  factory SessionPlaytimeCheckpoint.fromJson(Map<String, dynamic> j) =>
      SessionPlaytimeCheckpoint(
        j['id'] as String,
        DateTime.parse(j['startedAt'] as String),
        j['total'] as int,
        j['active'] as int,
      );
}

class TrackedPlaytimeCheckpoint {
  TrackedPlaytimeCheckpoint({
    required this.appId,
    required Map<String, SessionPlaytimeCheckpoint> sessions,
    this.hasOpenSession = false,
  }) : sessions = Map.unmodifiable(sessions) {
    if (appId <= 0 ||
        appId > 0xffffffff ||
        sessions.length > 10000 ||
        sessions.entries.any((e) => e.key != e.value.id)) {
      throw const FormatException('Invalid tracked playtime checkpoint');
    }
    var sum = 0;
    for (final value in sessions.values) {
      if (value.total > 0x1fffffffffffff - sum) {
        throw const FormatException('Tracked playtime exceeds supported range');
      }
      sum += value.total;
    }
  }
  final int appId;
  final Map<String, SessionPlaytimeCheckpoint> sessions;
  final bool hasOpenSession;
  int get total => sessions.values.fold(0, (n, s) => n + s.total);
  int get active => sessions.values.fold(0, (n, s) => n + s.active);

  factory TrackedPlaytimeCheckpoint.capture(
    int appId,
    Iterable<PlaySession> values,
  ) {
    final entries = <String, SessionPlaytimeCheckpoint>{};
    var open = false;
    try {
      for (final s in values.where((s) => s.gameId == appId)) {
        // Reuse persisted-session validation, without modifying the original.
        PlaySession.fromJson(s.toJson());
        if (entries.containsKey(s.id)) {
          throw const FormatException('Duplicate session');
        }
        entries[s.id] = SessionPlaytimeCheckpoint(
          s.id,
          s.startedAt,
          s.seconds,
          s.activeSeconds,
        );
        open = open || s.open;
      }
      return TrackedPlaytimeCheckpoint(
        appId: appId,
        sessions: entries,
        hasOpenSession: open,
      );
    } catch (_) {
      throw const PlaytimeReconciliationFailure(
        PlaytimeReconciliationIssue.invalidSessionData,
      );
    }
  }
  bool sameHistory(TrackedPlaytimeCheckpoint other) =>
      appId == other.appId &&
      hasOpenSession == other.hasOpenSession &&
      sessions.length == other.sessions.length &&
      sessions.entries.every(
        (e) => other.sessions[e.key]?.matches(e.value) == true,
      );
  bool retains(TrackedPlaytimeCheckpoint baseline) =>
      appId == baseline.appId &&
      baseline.sessions.entries.every(
        (e) => sessions[e.key]?.matches(e.value) == true,
      );

  Map<String, dynamic> toJson() => {
    'appId': appId,
    'hasOpenSession': hasOpenSession,
    'sessions': sessions.values.map((s) => s.toJson()).toList(),
  };
  factory TrackedPlaytimeCheckpoint.fromJson(Map<String, dynamic> j) {
    final entries = <String, SessionPlaytimeCheckpoint>{};
    for (final value in j['sessions'] as List) {
      final s = SessionPlaytimeCheckpoint.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      if (entries.containsKey(s.id)) {
        throw const FormatException('Duplicate checkpoint');
      }
      entries[s.id] = s;
    }
    return TrackedPlaytimeCheckpoint(
      appId: j['appId'] as int,
      sessions: entries,
      hasOpenSession: j['hasOpenSession'] as bool,
    );
  }
}

/// Accepted inputs are immutable. Revisions retain the entire earlier baseline.
class PlaytimeBaseline {
  PlaytimeBaseline({
    required this.account,
    required this.appId,
    required this.revision,
    required this.capturedAt,
    required this.acceptedAt,
    required this.source,
    required this.tracked,
    required this.historicalSeconds,
    required this.overlapEvidence,
    this.steamSnapshot,
    this.overlapSeconds,
    this.acceptedStaleSnapshot = false,
  }) {
    if (appId <= 0 ||
        appId > 0xffffffff ||
        revision <= 0 ||
        tracked.appId != appId ||
        tracked.hasOpenSession ||
        historicalSeconds < 0 ||
        historicalSeconds > 0x1fffffffffffff ||
        acceptedAt.isBefore(capturedAt) ||
        steamSnapshot != null &&
            (steamSnapshot!.account.steamId64 != account.steamId64 ||
                steamSnapshot!.appId != appId)) {
      throw const FormatException('Invalid playtime baseline');
    }
    if (source == HistoricalPlaytimeSource.manualHistorical) {
      if (overlapSeconds != null ||
          overlapEvidence != SteamOverlapEvidence.notApplicable) {
        throw const FormatException(
          'Manual history must not imply Steam overlap',
        );
      }
    } else {
      final steam = steamLifetimeAtBaselineSeconds;
      if (steam == null ||
          overlapSeconds == null ||
          overlapSeconds! < 0 ||
          overlapSeconds! > tracked.total ||
          overlapSeconds! > steam ||
          historicalSeconds != steam - overlapSeconds! ||
          ![
            SteamOverlapEvidence.userConfirmed,
            SteamOverlapEvidence.userAssumed,
            SteamOverlapEvidence.noTrackedRuntime,
            SteamOverlapEvidence.zeroSteamLifetime,
          ].contains(overlapEvidence) ||
          overlapEvidence == SteamOverlapEvidence.noTrackedRuntime &&
              tracked.total != 0 ||
          overlapEvidence == SteamOverlapEvidence.zeroSteamLifetime &&
              steam != 0 ||
          steamSnapshot!.state == SteamPlaytimeState.stale &&
              !acceptedStaleSnapshot) {
        throw const FormatException('Invalid accepted overlap evidence');
      }
    }
  }
  final SteamPlaytimeAccount account;
  final int appId, revision, historicalSeconds;
  final DateTime capturedAt, acceptedAt;
  final HistoricalPlaytimeSource source;
  final SteamPlaytimeSnapshot? steamSnapshot;
  final TrackedPlaytimeCheckpoint tracked;
  final int? overlapSeconds;
  final SteamOverlapEvidence overlapEvidence;
  final bool acceptedStaleSnapshot;
  String get key => '${account.steamId64}:$appId';
  int? get steamLifetimeAtBaselineSeconds =>
      steamSnapshot?.lifetimeMinutes == null
      ? null
      : steamSnapshot!.lifetimeMinutes! * 60;
  Map<String, dynamic> toJson() => {
    'steamId64': account.steamId64,
    'appId': appId,
    'revision': revision,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
    'source': source.name,
    'historicalSeconds': historicalSeconds,
    'tracked': tracked.toJson(),
    'overlapSeconds': overlapSeconds,
    'overlapEvidence': overlapEvidence.name,
    'acceptedStaleSnapshot': acceptedStaleSnapshot,
    'steamSnapshot': steamSnapshot?.toJson(),
  };
  factory PlaytimeBaseline.fromJson(Map<String, dynamic> j) => PlaytimeBaseline(
    account: SteamPlaytimeAccount(j['steamId64'] as String),
    appId: j['appId'] as int,
    revision: j['revision'] as int,
    capturedAt: DateTime.parse(j['capturedAt'] as String),
    acceptedAt: DateTime.parse(j['acceptedAt'] as String),
    source: HistoricalPlaytimeSource.values.byName(j['source'] as String),
    historicalSeconds: j['historicalSeconds'] as int,
    tracked: TrackedPlaytimeCheckpoint.fromJson(
      Map<String, dynamic>.from(j['tracked'] as Map),
    ),
    overlapSeconds: j['overlapSeconds'] as int?,
    overlapEvidence: SteamOverlapEvidence.values.byName(
      j['overlapEvidence'] as String,
    ),
    acceptedStaleSnapshot: j['acceptedStaleSnapshot'] as bool,
    steamSnapshot: j['steamSnapshot'] == null
        ? null
        : SteamPlaytimeSnapshot.fromJson(
            Map<String, dynamic>.from(j['steamSnapshot'] as Map),
          ),
  );
}

class CombinedPlaytimeResult {
  CombinedPlaytimeResult({
    required this.measuredActiveSeconds,
    this.combinedSeconds,
    this.baseline,
    Set<PlaytimeReconciliationIssue> issues = const {},
  }) : issues = Set.unmodifiable(issues);
  final int measuredActiveSeconds;
  final int? combinedSeconds;
  final PlaytimeBaseline? baseline;
  final Set<PlaytimeReconciliationIssue> issues;
}

/// Pure projection; never changes a baseline, session, snapshot or Activity total.
CombinedPlaytimeResult reconcilePlaytime({
  required PlaytimeBaseline? baseline,
  required SteamPlaytimeAccount? confirmedAccount,
  required TrackedPlaytimeCheckpoint current,
  required DateTime now,
  SteamPlaytimeSnapshot? latestSteam,
  Duration maxSnapshotAge = const Duration(hours: 24),
}) {
  CombinedPlaytimeResult blocked(PlaytimeReconciliationIssue issue) =>
      CombinedPlaytimeResult(
        measuredActiveSeconds: current.active,
        baseline: baseline,
        issues: {issue},
      );
  if (confirmedAccount == null) {
    return blocked(PlaytimeReconciliationIssue.accountNotConfirmed);
  }
  if (baseline == null) {
    return blocked(PlaytimeReconciliationIssue.baselineMissing);
  }
  if (baseline.account.steamId64 != confirmedAccount.steamId64 ||
      baseline.appId != current.appId ||
      latestSteam != null &&
          (latestSteam.account.steamId64 != confirmedAccount.steamId64 ||
              latestSteam.appId != current.appId)) {
    return blocked(PlaytimeReconciliationIssue.accountChanged);
  }
  if (!current.retains(baseline.tracked)) {
    return blocked(PlaytimeReconciliationIssue.sessionHistoryChanged);
  }
  final issues = <PlaytimeReconciliationIssue>{};
  if (latestSteam?.lifetimeMinutes == null) {
    issues.add(PlaytimeReconciliationIssue.steamUnavailable);
  } else {
    if (latestSteam!.staleAt(now, maxSnapshotAge)) {
      issues.add(PlaytimeReconciliationIssue.staleSteamSnapshot);
    }
    final old = baseline.steamLifetimeAtBaselineSeconds;
    if (old != null && latestSteam.lifetimeMinutes! * 60 < old) {
      issues.add(PlaytimeReconciliationIssue.steamCounterDecreased);
    }
  }
  return CombinedPlaytimeResult(
    measuredActiveSeconds: current.active,
    combinedSeconds: baseline.historicalSeconds + current.active,
    baseline: baseline,
    issues: issues,
  );
}
