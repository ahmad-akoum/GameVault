import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/models/playtime_reconciliation.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_local_playtime.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/activity_pages.dart';
import 'package:gamevault/ui/playtime_overview.dart';
import 'package:gamevault/ui/session_presentation.dart';
import 'package:gamevault/ui/theme.dart';
import 'steam_playtime_test.dart' show Fixture;
import 'playtime_reconciliation_test.dart' show session;
import 'services_test.dart' show TestMetadata, TestHltb;

void main() {
  late Fixture f;
  late VaultController c;
  setUp(() async {
    f = Fixture(
      await Directory.systemTemp.createTemp('gamevault_overview_test_'),
    );
    await f.initialize();
    c = VaultController(
      store: LocalStore(f.profile),
      scanner: SteamScanner(installationRoots: () async => []),
      metadata: TestMetadata(),
      hltb: TestHltb(),
      steamPlaytime: f.service,
    );
    await c.initialize();
    c.games = [
      VaultGame(
        appId: 11,
        title: 'Synthetic game',
        installPath: 'fixture',
        libraryPath: 'fixture',
      ),
    ];
    c.tracker.sessions.add(session(3600, 1800));
    c.settings = c.settings.copy(activityAdjusted: true);
    await c.refreshPlaytime();
  });
  tearDown(() async {
    await c.shutdown();
    expect(f.dir.path.startsWith(Directory.systemTemp.path), true);
    await f.dir.delete(recursive: true);
  });
  Future<void> confirm() async =>
      c.playtime!.confirm((await f.proposal()), c.steamAppIds);
  Future<void> accept({int history = 3600}) async {
    final p = c.playtime!;
    final proposal = await p.reconciliation.proposeManualHistorical(
      11,
      c.tracker.sessions,
      historicalSeconds: history,
    );
    await p.reconciliation.accept(proposal, c.tracker.sessions);
    await c.refreshPlaytime();
  }

  test(
    'automatic unconfirmed estimates are memory-only and excluded from Activity',
    () async {
      await c.refreshPlaytime(refresh: true, automatic: true);
      final p = c.playtime!;
      expect(p.provisional(11, c.tracker.sessions)?.combined, 5580);
      expect(p.provisional(11, c.tracker.sessions)?.historical, 3780);
      expect(p.data.confirmedAccount, isNull);
      expect(p.data.baselines, isEmpty);
      expect(await f.store.file.exists(), false);
      expect(c.lifetimePlayed(11), 1800);
      expect(c.hasCombinedPlaytime, false);
    },
  );
  test(
    'automatic reads throttle; concurrent manual refreshes coalesce; unchanged identity checks stay quiet',
    () async {
      var reads = 0, notifications = 0;
      f.overrideRead = (path) async {
        if (path.endsWith('localconfig.vdf')) reads++;
        return readSteamDocument(path);
      };
      final p = c.playtime!;
      await c.refreshPlaytime(refresh: true, automatic: true);
      expect(reads, 1);
      p.addListener(() => notifications++);
      for (var i = 0; i < 4; i++) {
        f.clock = f.clock.add(const Duration(minutes: 1));
        await c.refreshPlaytime(refresh: true, automatic: true);
      }
      expect(reads, 1);
      expect(notifications, 0);
      f.clock = f.clock.add(const Duration(minutes: 1));
      await c.refreshPlaytime(refresh: true, automatic: true);
      expect(reads, 2);
      await Future.wait(
        List.generate(10, (_) => c.refreshPlaytime(refresh: true)),
      );
      expect(reads, 3);
      expect(p.busy, false);
      expect(p.refreshing, false);
    },
  );
  test(
    'manual refresh burst behind an identity check drains once; indicators reflect actual work',
    () async {
      final identityStarted = Completer<void>(),
          identityGate = Completer<void>();
      final cacheStarted = Completer<void>(), cacheGate = Completer<void>();
      var reads = 0;
      f.overrideRead = (path) async {
        if (path.endsWith('loginusers.vdf')) {
          if (!identityStarted.isCompleted) identityStarted.complete();
          await identityGate.future;
        }
        if (path.endsWith('localconfig.vdf')) {
          reads++;
          if (!cacheStarted.isCompleted) cacheStarted.complete();
          await cacheGate.future;
        }
        return readSteamDocument(path);
      };
      final identity = c.refreshPlaytime();
      await identityStarted.future.timeout(const Duration(seconds: 5));
      expect(c.playtime!.busy, true);
      expect(c.playtime!.refreshing, false);
      final requests = List.generate(
        10,
        (_) => c.refreshPlaytime(refresh: true),
      );
      identityGate.complete();
      await cacheStarted.future.timeout(const Duration(seconds: 5));
      expect(c.playtime!.refreshing, true);
      cacheGate.complete();
      await Future.wait([identity, ...requests]);
      expect(reads, 1);
      expect(c.playtime!.busy, false);
      expect(c.playtime!.refreshing, false);
    },
  );
  test(
    'provisional estimates reject missing stale and impossible full overlap without clamping',
    () async {
      for (final value in ['"11" {}', '"11" { "Playtime" "1" }']) {
        await f.writeCache(value);
        await c.refreshPlaytime(refresh: true);
        expect(c.playtime!.provisional(11, c.tracker.sessions), isNull);
      }
      await f.writeCache(
        '"11" { "Playtime" "200" }',
        modified: f.clock.subtract(const Duration(days: 3)),
      );
      await c.refreshPlaytime(refresh: true);
      expect(c.playtime!.provisional(11, c.tracker.sessions), isNull);
      expect(c.lifetimePlayed(11), 1800);
    },
  );
  test(
    'shutdown drains an in-flight cache read and rejects new background work',
    () async {
      final started = Completer<void>(), gate = Completer<void>();
      var reads = 0, closed = false;
      f.overrideRead = (path) async {
        if (path.endsWith('localconfig.vdf')) {
          reads++;
          if (!started.isCompleted) started.complete();
          await gate.future;
        }
        return readSteamDocument(path);
      };
      final reading = c.refreshPlaytime(refresh: true, automatic: true);
      await started.future.timeout(const Duration(seconds: 5));
      final closing = c.playtime!.close().then((_) => closed = true);
      await c.playtime!.load([11], refresh: true);
      expect(closed, false);
      expect(reads, 1);
      gate.complete();
      await Future.wait([reading, closing]);
      expect(closed, true);
      expect(c.playtime!.busy, false);
    },
  );
  test(
    'accepted manual histories take precedence; account changes never reuse automatic data',
    () async {
      await c.refreshPlaytime(refresh: true);
      expect(c.playtime!.provisional(11, c.tracker.sessions), isNotNull);
      await confirm();
      await accept(history: 0);
      final before = jsonEncode(
        c.playtime!.data.baselines.values.single.single.toJson(),
      );
      await c.refreshPlaytime(refresh: true);
      expect(c.playtime!.provisional(11, c.tracker.sessions), isNull);
      expect(c.lifetimePlayed(11), 1800);
      expect(
        jsonEncode(c.playtime!.data.baselines.values.single.single.toJson()),
        before,
      );
      f.active = SteamActiveProcess(202, 124, f.exe.path);
      await c.refreshPlaytime(refresh: true);
      expect(c.playtime!.snapshotFor(11), isNull);
      expect(c.playtime!.provisional(11, c.tracker.sessions), isNull);
      expect(c.playtime!.data.confirmedAccount!.steamId64, f.first.steamId64);
    },
  );

  test(
    'UI state never confirms automatically and no baseline means measured fallback',
    () async {
      await c.refreshPlaytime(refresh: true);
      expect(c.playtime!.data.confirmedAccount, isNull);
      expect(
        c.playtime!.detection!.proposal!.account.steamId64,
        f.first.steamId64,
      );
      expect(c.lifetimePlayed(11), 1800);
      expect(c.playtime!.data.baselines, isEmpty);
    },
  );
  test(
    'explicit confirmation then preview does not enter lifetime totals until acceptance',
    () async {
      await confirm();
      final p = c.playtime!;
      final proposal = await p.reconciliation.proposeSteam(
        11,
        c.tracker.sessions,
        overlapSeconds: 3600,
        evidence: SteamOverlapEvidence.userAssumed,
      );
      expect(c.lifetimePlayed(11), 1800);
      await p.reconciliation.accept(proposal, c.tracker.sessions);
      await c.refreshPlaytime();
      expect(c.lifetimePlayed(11), 5580);
      expect(c.played(11), 1800);
      expect(c.hasCombinedPlaytime, true);
    },
  );
  test(
    'manual missing-cache history, refreshes and revisions keep sessions and daily data exact',
    () async {
      await confirm();
      await f.writeCache('"11" {}');
      await c.refreshPlaytime(refresh: true);
      final before = jsonEncode(c.tracker.toJson());
      await accept();
      expect(c.lifetimePlayed(11), 5400);
      expect(c.playtime!.data.latest.values.single.lifetimeMinutes, isNull);
      await f.writeCache('"11" { "Playtime" "900" }');
      await c.refreshPlaytime(refresh: true);
      expect(c.lifetimePlayed(11), 5400);
      await accept(history: 0);
      expect(c.lifetimePlayed(11), 1800);
      expect(c.playtime!.data.baselines.values.single.length, 2);
      expect(jsonEncode(c.tracker.toJson()), before);
    },
  );
  test(
    'account switch or missing identity suppresses accepted estimate without rebinding',
    () async {
      await confirm();
      await accept();
      f.active = SteamActiveProcess(202, 124, f.exe.path);
      await c.refreshPlaytime(refresh: true);
      expect(c.lifetimePlayed(11), 1800);
      expect(
        c.playtime!.estimate(11, c.tracker.sessions).issues,
        contains(PlaytimeReconciliationIssue.accountChanged),
      );
      expect(c.playtime!.data.confirmedAccount!.steamId64, f.first.steamId64);
      await c.playtime!.confirm(await f.proposal(), c.steamAppIds);
      expect(
        c.playtime!.estimate(11, c.tracker.sessions).issues,
        contains(PlaytimeReconciliationIssue.baselineMissing),
      );
      f.active = null;
      await c.refreshPlaytime();
      expect(c.lifetimePlayed(11), 1800);
    },
  );
  test(
    'identity expires and session edits require review; total-session setting unchanged',
    () async {
      await confirm();
      await accept();
      c.settings = c.settings.copy(activityAdjusted: false);
      expect(c.lifetimePlayed(11), 3600);
      expect(c.hasCombinedPlaytime, false);
      c.settings = c.settings.copy(activityAdjusted: true);
      f.clock = f.clock.add(const Duration(minutes: 3));
      expect(c.lifetimePlayed(11), 1800);
      await c.refreshPlaytime();
      expect(c.lifetimePlayed(11), 5400);
      c.tracker.sessions.clear();
      expect(
        c.playtime!.estimate(11, c.tracker.sessions).issues,
        contains(PlaytimeReconciliationIssue.sessionHistoryChanged),
      );
    },
  );
  test(
    'refresh warns on stale or decreased Steam input but preserves baseline',
    () async {
      await confirm();
      await accept();
      await f.writeCache(
        '"11" { "Playtime" "1" }',
        modified: f.clock.subtract(const Duration(days: 3)),
      );
      await c.refreshPlaytime(refresh: true);
      final result = c.playtime!.estimate(11, c.tracker.sessions);
      expect(
        result.issues,
        containsAll([
          PlaytimeReconciliationIssue.staleSteamSnapshot,
          PlaytimeReconciliationIssue.steamCounterDecreased,
        ]),
      );
      expect(c.lifetimePlayed(11), 5400);
    },
  );
  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'overview and setup stay responsive at $width without accepting preview',
      (tester) async {
        await tester.runAsync(() async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Future<void> settleIo() async {
            await tester.pumpAndSettle();
            for (var i = 0; i < 60; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await tester.pump();
              if (!c.playtime!.busy && i > 3) break;
            }
            await tester.pumpAndSettle();
          }

          await tester.pumpWidget(
            MaterialApp(
              theme: vaultTheme(
                width == 360 ? Brightness.light : Brightness.dark,
                0xff78aaff,
              ),
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => SingleChildScrollView(
                    child: PlaytimeOverview(
                      controller: c,
                      game: c.games.single,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('GameVault measured active time'), findsOneWidget);
          await tester.ensureVisible(find.text('Adjust'));
          await tester.tap(find.text('Adjust'));
          await settleIo();
          expect(find.text('Confirm this Steam account'), findsOneWidget);
          {
            await tester.tap(find.text('Confirm this Steam account'));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await settleIo();
          expect(
            c.playtime!.accountMatches,
            true,
            reason: 'busy=${c.playtime!.busy} message=${c.playtime!.message}',
          );
          await tester.ensureVisible(
            find.byType(DropdownButtonFormField<HistoryChoice>),
          );
          await tester.tap(find.byType(DropdownButtonFormField<HistoryChoice>));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text('Zero history — tracked from the start').last,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(CheckboxListTile).last);
          await tester.tap(find.byType(CheckboxListTile).last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Preview calculation'));
          {
            await tester.tap(find.text('Preview calculation'));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await tester.pumpAndSettle();
          expect(find.textContaining('UNACCEPTED PREVIEW'), findsOneWidget);
          expect(c.playtime!.data.baselines, isEmpty);
          expect(c.lifetimePlayed(11), 1800);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(c.playtime!.data.baselines, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }
  for (final scenario in [
    (HistoryChoice.fullOverlap, 'Full tracked runtime overlaps Steam', 5580),
    (HistoryChoice.partialOverlap, 'Partial overlap — enter runtime', 7380),
    (HistoryChoice.manualHistory, 'Manual historical-only time', 3600),
  ]) {
    testWidgets('setup accepts ${scenario.$1.name} only after preview', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await confirm();
        if (scenario.$1 == HistoryChoice.manualHistory) {
          await f.writeCache('"11" {}');
          await c.refreshPlaytime(refresh: true);
        }
        Future<void> flush(bool Function() ready) async {
          for (var i = 0; i < 150; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (i > 3 && ready()) {
              await tester.pumpAndSettle();
              return;
            }
          }
          fail(
            'UI operation did not finish: baselines=${c.playtime!.data.baselines.length}; ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}',
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlaytimeOverview(controller: c, game: c.games.single),
              ),
            ),
          ),
        );
        await tester.ensureVisible(find.text('Adjust'));
        await tester.tap(find.text('Adjust'));
        await tester.pumpAndSettle();
        await flush(() => !c.playtime!.busy);
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<HistoryChoice>),
        );
        await tester.tap(find.byType(DropdownButtonFormField<HistoryChoice>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(scenario.$2).last);
        await tester.pumpAndSettle();
        if (scenario.$1 != HistoryChoice.fullOverlap) {
          await tester.ensureVisible(find.byType(TextField).at(1));
          await tester.enterText(find.byType(TextField).at(1), '30');
        }
        await tester.ensureVisible(find.byType(CheckboxListTile).last);
        await tester.tap(find.byType(CheckboxListTile).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Preview calculation'));
        await tester.tap(find.text('Preview calculation'));
        await flush(
          () => find.textContaining('UNACCEPTED PREVIEW').evaluate().isNotEmpty,
        );
        expect(c.playtime!.data.baselines, isEmpty);
        await tester.tap(find.text('Accept baseline'));
        await flush(() => c.playtime!.data.baselines.isNotEmpty);
        expect(c.lifetimePlayed(11), scenario.$3);
        expect(c.tracker.sessions.length, 1);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
  testWidgets(
    'compact panel labels provisional estimates and moves metadata into information',
    (tester) async {
      await tester.runAsync(
        () => c.refreshPlaytime(refresh: true, automatic: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaytimeOverview(controller: c, game: c.games.single),
          ),
        ),
      );
      expect(find.text('Provisional 1h 33m'), findsOneWidget);
      expect(find.text('Estimated activity-adjusted lifetime'), findsNothing);
      expect(find.text('Steam lifetime'), findsOneWidget);
      expect(find.text('GameVault active'), findsOneWidget);
      expect(find.text('GameVault inactive'), findsOneWidget);
      expect(find.text('Historical adjustment'), findsOneWidget);
      expect(find.textContaining('Retrieved:'), findsNothing);
      expect(find.textContaining('Profile-based estimate:'), findsNothing);
      expect(c.hasCombinedPlaytime, false);
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.textContaining('Profile-based estimate:'), findsOneWidget);
      expect(find.textContaining('Retrieved:'), findsOneWidget);
      expect(
        find.textContaining('Provisional estimates are never used'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'release footers distinguish accepted overlap, manual/zero history and unavailable states',
    () async {
      await confirm();
      final p = c.playtime!;
      for (final entry in [(3600, 'Full'), (1800, 'Partial'), (0, 'Zero')]) {
        final proposal = await p.reconciliation.proposeSteam(
          11,
          c.tracker.sessions,
          overlapSeconds: entry.$1,
          evidence: SteamOverlapEvidence.userAssumed,
        );
        final b = await p.reconciliation.accept(proposal, c.tracker.sessions);
        expect(
          overviewFooter(
            baseline: b,
            accepted: true,
            provisional: false,
            steam: true,
            available: true,
          ),
          'Steam · ${entry.$2} overlap assumed',
        );
      }
      await accept(history: 0);
      expect(
        overviewFooter(
          baseline: p.estimate(11, c.tracker.sessions).baseline,
          accepted: true,
          provisional: false,
          steam: true,
          available: true,
        ),
        'Manual · Zero history',
      );
      await accept(history: 3600);
      expect(
        overviewFooter(
          baseline: p.estimate(11, c.tracker.sessions).baseline,
          accepted: true,
          provisional: false,
          steam: true,
          available: true,
        ),
        'Manual · Historical-only time',
      );
      expect(
        overviewFooter(
          accepted: false,
          provisional: true,
          steam: true,
          available: true,
        ),
        'Steam · Full overlap assumed · Provisional',
      );
      expect(
        overviewFooter(
          accepted: false,
          provisional: false,
          steam: true,
          available: false,
        ),
        contains('Steam unavailable'),
      );
      expect(
        overviewFooter(
          accepted: false,
          provisional: false,
          steam: false,
          available: false,
        ),
        'GameVault · Measured active time',
      );
    },
  );
  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'release accepted headline and rounded Adjust remain clear at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.runAsync(() async {
          await confirm();
          await accept();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: vaultTheme(
              width == 360 ? Brightness.light : Brightness.dark,
              0xff78aaff,
            ),
            home: Scaffold(
              body: PlaytimeOverview(controller: c, game: c.games.single),
            ),
          ),
        );
        expect(find.text('Estimated 1h 30m'), findsOneWidget);
        expect(find.text('Estimated activity-adjusted lifetime'), findsNothing);
        expect(find.byIcon(Icons.tune), findsOneWidget);
        expect(
          find.byWidgetPredicate((w) => w is FilledButton),
          findsOneWidget,
        );
        expect(find.byTooltip('Playtime information'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'Activity lifetime summary and rankings use estimate but charts and counts use sessions',
    (tester) async {
      await tester.runAsync(() async {
        await confirm();
        await accept();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatisticsPage(controller: c, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LIFETIME ESTIMATE'), findsOneWidget);
      expect(find.text(sessionDuration(5400)), findsWidgets);
      expect(find.text('SESSIONS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Synthetic game'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Accepted lifetime estimate'), findsOneWidget);
      expect(c.tracker.sessions.single.seconds, 3600);
      expect(c.tracker.sessions.single.activeSeconds, 1800);
      expect(c.tracker.sessions.single.daily.values.single, 3600);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
