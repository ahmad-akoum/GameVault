import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/models/play_session.dart';
import 'package:gamevault/models/playtime_reconciliation.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/playtime_reconciliation_service.dart';
import 'package:gamevault/services/steam_local_playtime.dart';
import 'package:gamevault/services/steam_playtime_store.dart';
import 'steam_playtime_test.dart' show Fixture;

PlaySession session(
  int total,
  int active, {
  String id = 'one',
  int appId = 11,
  bool open = false,
}) {
  final start = DateTime.utc(2026, 11, 1);
  return PlaySession(
    id: id,
    gameId: appId,
    title: 'Synthetic fixture',
    startedAt: start,
    lastObservedAt: start.add(Duration(seconds: total)),
    endedAt: open ? null : start.add(Duration(seconds: total)),
    seconds: total,
    activeSeconds: active,
    daily: {'2026-11-01': total},
    activeDaily: {'2026-11-01': active},
  );
}

Matcher failure(PlaytimeReconciliationIssue issue) =>
    isA<PlaytimeReconciliationFailure>().having((e) => e.issue, 'issue', issue);

void main() {
  late Fixture f;
  late PlaytimeReconciliationService r;
  late List<PlaySession> sessions;
  Future<void> cache(int? minutes, {int appId = 11}) async {
    await f.writeCache(
      minutes == null ? '"$appId" {}' : '"$appId" { "Playtime" "$minutes" }',
    );
    await f.service.refresh([appId]);
  }

  Future<PlaytimeBaseline> acceptSteam({
    int? overlap,
    SteamOverlapEvidence evidence = SteamOverlapEvidence.userConfirmed,
  }) async {
    final proposal = await r.proposeSteam(
      11,
      sessions,
      overlapSeconds: overlap ?? 3600,
      evidence: evidence,
    );
    return r.accept(proposal, sessions);
  }

  setUp(() async {
    f = Fixture(
      await Directory.systemTemp.createTemp('gamevault_reconcile_test_'),
    );
    await f.initialize();
    await f.confirm();
    await f.service.refresh([11]);
    r = PlaytimeReconciliationService(f.service, now: () => f.clock);
    sessions = [session(3600, 1800)];
  });
  tearDown(() async {
    expect(p.isWithin(Directory.systemTemp.path, f.dir.path), true);
    await f.dir.delete(recursive: true);
  });

  test(
    'synthetic full overlap preserves second-level tracked precision',
    () async {
      const appId = 42;
      final values = [session(3661, 1827, appId: appId)];
      await cache(120, appId: appId);
      final proposal = await r.proposeSteam(
        appId,
        values,
        overlapSeconds: 3661,
        evidence: SteamOverlapEvidence.userConfirmed,
      );
      final b = await r.accept(proposal, values);
      expect(b.steamLifetimeAtBaselineSeconds, 7200);
      expect(b.tracked.total, 3661);
      expect(b.tracked.active, 1827);
      expect(b.historicalSeconds, 3539);
      expect((await r.evaluate(appId, values)).combinedSeconds, 5366);
    },
  );

  test(
    'no automatic overlap when Steam and tracked totals are nonzero',
    () async {
      final before = await f.store.file.readAsBytes();
      await expectLater(
        r.proposeSteam(11, sessions),
        throwsA(failure(PlaytimeReconciliationIssue.overlapRequired)),
      );
      await expectLater(
        r.proposeSteam(11, sessions, overlapSeconds: 3600),
        throwsA(failure(PlaytimeReconciliationIssue.overlapRequired)),
      );
      expect(await f.store.file.readAsBytes(), before);
      expect((await r.evaluate(11, sessions)).combinedSeconds, isNull);
    },
  );

  test(
    'partial overlap, assumed overlap and confirmed zero overlap are explicit',
    () async {
      await cache(120);
      final partial = await acceptSteam(
        overlap: 1800,
        evidence: SteamOverlapEvidence.userAssumed,
      );
      expect(partial.historicalSeconds, 5400);
      expect(partial.overlapEvidence, SteamOverlapEvidence.userAssumed);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 7200);
      await acceptSteam(overlap: 0);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 9000);
      expect((await f.store.load()).baselines[partial.key]!.length, 2);
    },
  );

  test(
    'invalid overlap never clamps into an apparently valid history',
    () async {
      for (final overlap in [-1, 3601, 999999]) {
        await expectLater(
          r.proposeSteam(
            11,
            sessions,
            overlapSeconds: overlap,
            evidence: SteamOverlapEvidence.userConfirmed,
          ),
          throwsA(failure(PlaytimeReconciliationIssue.invalidOverlap)),
        );
      }
    },
  );

  test(
    'explicit Steam zero retains active time, subsequent Steam growth adds nothing',
    () async {
      await cache(0);
      final proposed = await r.proposeSteam(11, sessions);
      final baseline = await r.accept(proposed, sessions);
      expect(baseline.historicalSeconds, 0);
      expect(baseline.overlapEvidence, SteamOverlapEvidence.zeroSteamLifetime);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 1800);
      await cache(90);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 1800);
      sessions.add(session(600, 300, id: 'next'));
      expect((await r.evaluate(11, sessions)).combinedSeconds, 2100);
    },
  );

  test(
    'game tracked from zero with nonzero Steam runtime accepts zero history',
    () async {
      await cache(60);
      final b = await acceptSteam();
      expect(b.historicalSeconds, 0);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 1800);
    },
  );

  test(
    'no tracked runtime supports zero overlap without claiming all sessions overlap',
    () async {
      sessions = [session(0, 0)];
      final proposed = await r.proposeSteam(11, sessions);
      final b = await r.accept(proposed, sessions);
      expect(b.overlapEvidence, SteamOverlapEvidence.noTrackedRuntime);
      expect(b.overlapSeconds, 0);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 7380);
    },
  );

  test(
    'missing Steam is unavailable despite last-known data; manual fallback works',
    () async {
      await cache(null);
      await expectLater(
        r.proposeSteam(
          11,
          sessions,
          overlapSeconds: 3600,
          evidence: SteamOverlapEvidence.userConfirmed,
        ),
        throwsA(failure(PlaytimeReconciliationIssue.steamUnavailable)),
      );
      final draft = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 9000,
      );
      final b = await r.accept(draft, sessions);
      expect(b.source, HistoricalPlaytimeSource.manualHistorical);
      expect(b.steamLifetimeAtBaselineSeconds, isNull);
      expect(b.overlapSeconds, isNull);
      final result = await r.evaluate(11, sessions);
      expect(result.combinedSeconds, 10800);
      expect(
        result.issues,
        contains(PlaytimeReconciliationIssue.steamUnavailable),
      );
    },
  );

  test(
    'manual zero is explicit no-history input, never an inferred missing value',
    () async {
      await cache(null);
      final proposal = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 0,
      );
      final b = await r.accept(proposal, sessions);
      expect(b.source, HistoricalPlaytimeSource.manualHistorical);
      expect(b.steamSnapshot!.lifetimeMinutes, isNull);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 1800);
      await expectLater(
        r.proposeManualHistorical(11, sessions, historicalSeconds: -1),
        throwsA(failure(PlaytimeReconciliationIssue.invalidHistoricalValue)),
      );
    },
  );

  test(
    'confirmed no-history manual zero ignores Steam rounding or excess runtime',
    () async {
      await cache(61);
      final proposal = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 0,
      );
      final b = await r.accept(proposal, sessions);
      expect(b.steamLifetimeAtBaselineSeconds, 3660);
      expect(b.historicalSeconds, 0);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 1800);
      sessions = [session(3601, 1800)];
      await cache(60);
      await expectLater(
        r.proposeSteam(
          11,
          sessions,
          overlapSeconds: 3601,
          evidence: SteamOverlapEvidence.userConfirmed,
        ),
        throwsA(failure(PlaytimeReconciliationIssue.invalidOverlap)),
      );
    },
  );

  test(
    'stale Steam needs explicit acknowledgement before acceptance',
    () async {
      f.clock = f.clock.add(const Duration(days: 2));
      await expectLater(
        r.proposeSteam(
          11,
          sessions,
          overlapSeconds: 3600,
          evidence: SteamOverlapEvidence.userConfirmed,
        ),
        throwsA(failure(PlaytimeReconciliationIssue.staleSteamSnapshot)),
      );
      final proposal = await r.proposeSteam(
        11,
        sessions,
        overlapSeconds: 3600,
        evidence: SteamOverlapEvidence.userConfirmed,
        allowStaleSnapshot: true,
      );
      final b = await r.accept(proposal, sessions);
      expect(b.acceptedStaleSnapshot, true);
      expect(
        (await r.evaluate(11, sessions)).issues,
        contains(PlaytimeReconciliationIssue.staleSteamSnapshot),
      );
    },
  );

  test(
    'preview expiring with time cannot silently accept a stale snapshot',
    () async {
      final draft = await r.proposeSteam(
        11,
        sessions,
        overlapSeconds: 3600,
        evidence: SteamOverlapEvidence.userConfirmed,
      );
      f.clock = f.clock.add(const Duration(days: 2));
      await expectLater(
        r.accept(draft, sessions),
        throwsA(failure(PlaytimeReconciliationIssue.staleSteamSnapshot)),
      );
      expect((await f.store.load()).baselines, isEmpty);
    },
  );

  test(
    'refresh and Steam decreases preserve the accepted baseline exactly',
    () async {
      final b = await acceptSteam();
      final original = jsonEncode(b.toJson());
      final expected = (await r.evaluate(11, sessions)).combinedSeconds;
      for (final minutes in [200, 200, 100]) {
        await cache(minutes);
      }
      final data = await f.store.load();
      expect(jsonEncode(data.baselines[b.key]!.single.toJson()), original);
      final result = await r.evaluate(11, sessions);
      expect(result.combinedSeconds, expected);
      expect(
        result.issues,
        contains(PlaytimeReconciliationIssue.steamCounterDecreased),
      );
      await cache(null);
      expect((await r.evaluate(11, sessions)).combinedSeconds, expected);
      expect(
        (await r.evaluate(11, sessions)).issues,
        contains(PlaytimeReconciliationIssue.steamUnavailable),
      );
    },
  );

  test(
    'only additional measured active seconds increase the combined estimate',
    () async {
      await acceptSteam();
      final before = (await r.evaluate(11, sessions)).combinedSeconds!;
      sessions.add(session(600, 20, id: 'mostly-inactive', open: true));
      expect((await r.evaluate(11, sessions)).combinedSeconds, before + 20);
      sessions.add(session(100, 100, id: 'different-game', appId: 12));
      expect((await r.evaluate(11, sessions)).combinedSeconds, before + 20);
    },
  );

  test(
    'open sessions block baseline creation and history changes invalidate preview',
    () async {
      sessions = [session(3600, 1800, open: true)];
      await expectLater(
        r.proposeSteam(11, sessions),
        throwsA(failure(PlaytimeReconciliationIssue.gameRunning)),
      );
      sessions = [session(3600, 1800)];
      final draft = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 0,
      );
      sessions.add(session(60, 60, id: 'another'));
      await expectLater(
        r.accept(draft, sessions),
        throwsA(failure(PlaytimeReconciliationIssue.sessionHistoryChanged)),
      );
    },
  );

  test(
    'changed or deleted baseline sessions require review, not recalculation',
    () async {
      await acceptSteam();
      sessions = [session(3600, 1801)];
      expect(
        (await r.evaluate(11, sessions)).issues,
        contains(PlaytimeReconciliationIssue.sessionHistoryChanged),
      );
      expect((await r.evaluate(11, sessions)).combinedSeconds, isNull);
      sessions = [session(9000, 8000, id: 'replacement')];
      expect((await r.evaluate(11, sessions)).combinedSeconds, isNull);
    },
  );

  test(
    'incomplete activity and duplicate session IDs are rejected rather than filled',
    () async {
      sessions.single.activeDaily.clear();
      await expectLater(
        r.proposeManualHistorical(11, sessions, historicalSeconds: 0),
        throwsA(failure(PlaytimeReconciliationIssue.invalidSessionData)),
      );
      sessions = [session(3600, 1800), session(10, 10)];
      await expectLater(
        r.proposeManualHistorical(11, sessions, historicalSeconds: 0),
        throwsA(failure(PlaytimeReconciliationIssue.invalidSessionData)),
      );
    },
  );

  test('accepting a preview twice cannot duplicate accepted history', () async {
    final proposal = await r.proposeManualHistorical(
      11,
      sessions,
      historicalSeconds: 100,
    );
    final b = await r.accept(proposal, sessions);
    await expectLater(
      r.accept(proposal, sessions),
      throwsA(failure(PlaytimeReconciliationIssue.proposalExpired)),
    );
    expect((await f.store.load()).baselines[b.key]!.length, 1);
    expect((await r.evaluate(11, sessions)).combinedSeconds, 1900);
  });

  test(
    'explicit rebaselining appends a revision and preserves all accepted inputs',
    () async {
      final original = await acceptSteam();
      final proposal = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 42,
      );
      final revised = await r.accept(proposal, sessions);
      final history = (await f.store.load()).baselines[original.key]!;
      expect(history.map((b) => b.revision), [1, 2]);
      expect(jsonEncode(history.first.toJson()), jsonEncode(original.toJson()));
      expect(revised.source, HistoricalPlaytimeSource.manualHistorical);
      expect((await r.evaluate(11, sessions)).combinedSeconds, 1842);
    },
  );

  test(
    'snapshot refresh between preview and acceptance expires the proposal',
    () async {
      final proposal = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 0,
      );
      f.clock = f.clock.add(const Duration(minutes: 1));
      await cache(124);
      await expectLater(
        r.accept(proposal, sessions),
        throwsA(failure(PlaytimeReconciliationIssue.proposalExpired)),
      );
    },
  );

  test(
    'account changes block proposal, acceptance and evaluation without rebind',
    () async {
      final b = await acceptSteam();
      final proposed = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 1,
      );
      f.active = SteamActiveProcess(202, 124, f.exe.path);
      await expectLater(
        r.proposeManualHistorical(11, sessions, historicalSeconds: 1),
        throwsA(failure(PlaytimeReconciliationIssue.accountChanged)),
      );
      await expectLater(
        r.accept(proposed, sessions),
        throwsA(failure(PlaytimeReconciliationIssue.accountChanged)),
      );
      expect((await r.evaluate(11, sessions)).combinedSeconds, isNull);
      final newAccount = (await f.service.proposeAccount()).proposal!;
      await f.service.confirmAccount(newAccount);
      await f.service.refresh([11]);
      expect(
        (await r.evaluate(11, sessions)).issues,
        contains(PlaytimeReconciliationIssue.baselineMissing),
      );
      expect((await f.store.load()).baselines[b.key]!.length, 1);
    },
  );

  test(
    'unavailable active identity and unconfirmed accounts fail closed',
    () async {
      await acceptSteam();
      f.active = null;
      expect(
        (await r.evaluate(11, sessions)).issues,
        contains(PlaytimeReconciliationIssue.accountUnavailable),
      );
      final other = SteamPlaytimeStore(
        Directory(p.join(f.dir.path, 'unconfirmed')),
      );
      final data = await other.load();
      final projected = reconcilePlaytime(
        baseline: null,
        confirmedAccount: data.confirmedAccount,
        current: TrackedPlaytimeCheckpoint.capture(11, sessions),
        now: f.clock,
      );
      expect(projected.combinedSeconds, isNull);
      expect(
        projected.issues,
        contains(PlaytimeReconciliationIssue.accountNotConfirmed),
      );
    },
  );

  test(
    'sidecar v1 migrates additively, baseline and snapshots survive restart',
    () async {
      final original = await f.store.file.readAsString();
      final legacy = jsonDecode(original) as Map<String, dynamic>;
      legacy['version'] = 1;
      legacy.remove('baselines');
      await f.store.file.writeAsString(jsonEncode(legacy));
      expect((await f.store.load()).baselines, isEmpty);
      final baseline = await acceptSteam();
      final data = await SteamPlaytimeStore(f.profile).load();
      expect(data.toJson()['version'], 2);
      expect(data.latest.values.single.lifetimeMinutes, 123);
      expect(
        jsonEncode(data.baselines[baseline.key]!.single.toJson()),
        jsonEncode(baseline.toJson()),
      );
      final tampered = data.toJson();
      ((tampered['baselines'] as List).single as Map)['historicalSeconds'] = 1;
      expect(() => SteamPlaytimeData.fromJson(tampered), throwsFormatException);
    },
  );

  test(
    'failed baseline persistence retains the previous accepted revision',
    () async {
      final b = await acceptSteam();
      final proposed = await r.proposeManualHistorical(
        11,
        sessions,
        historicalSeconds: 999,
      );
      final before = await f.store.file.readAsBytes();
      final backup = File('${f.store.file.path}.bak');
      await backup.rename('${backup.path}.saved');
      await Directory(backup.path).create();
      await expectLater(
        r.accept(proposed, sessions),
        throwsA(isA<SteamPlaytimeStorageFailure>()),
      );
      expect(await f.store.file.readAsBytes(), before);
      expect((await f.store.load()).baselines[b.key]!.length, 1);
    },
  );

  test(
    'recovery cannot silently roll accepted baseline history back',
    () async {
      await acceptSteam();
      final backup = File('${f.store.file.path}.bak');
      final before = await backup.readAsBytes();
      await f.store.file.writeAsString('{');
      final result = await r.evaluate(11, sessions);
      expect(result.combinedSeconds, isNull);
      expect(
        result.issues,
        contains(PlaytimeReconciliationIssue.sidecarRecoveryRequired),
      );
      await expectLater(
        f.service.refresh([11]),
        throwsA(isA<SteamPlaytimeStorageFailure>()),
      );
      expect(await f.store.file.readAsString(), '{');
      expect(await backup.readAsBytes(), before);
    },
  );

  test(
    'existing vault, daily allocations and sessions remain byte-identical',
    () async {
      final local = LocalStore(f.profile);
      await local.save(
        [
          VaultGame(
            appId: 11,
            title: 'Fixture',
            installPath: 'fixture',
            libraryPath: 'fixture',
          ),
        ],
        const VaultSettings(),
        sessions: sessions.map((s) => s.toJson()).toList(),
      );
      final vault = await local.file.readAsBytes();
      final inputs = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await acceptSteam();
      await cache(999);
      await r.evaluate(11, sessions);
      expect(await local.file.readAsBytes(), vault);
      expect(jsonEncode(sessions.map((s) => s.toJson()).toList()), inputs);
      expect((await local.load()).sessions.single, sessions.single.toJson());
    },
  );
}
