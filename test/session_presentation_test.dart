import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/models/play_session.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/activity_pages.dart';
import 'package:gamevault/ui/appearance_controls.dart';
import 'package:gamevault/ui/details_page.dart';
import 'package:gamevault/ui/session_presentation.dart';
import 'package:gamevault/ui/theme.dart';
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

PlaySession fixture(
  int total,
  int active, {
  bool unknown = false,
  bool running = false,
}) {
  final start = DateTime(2026, 10, 17, 10, 20, 30);
  return PlaySession(
    id: 'fixture-$total-$active',
    gameId: 1,
    title: 'Example game',
    startedAt: start,
    lastObservedAt: start.add(Duration(seconds: total)),
    endedAt: running ? null : start.add(Duration(seconds: total)),
    seconds: total,
    activeSeconds: active,
    reason: running ? null : 'Process ended',
    daily: unknown || total == 0 ? {} : {dateKey(start): total},
    activeDaily: unknown || active == 0 ? {} : {dateKey(start): active},
  );
}

void main() {
  final durations = {
    0: '0s',
    1: '1s',
    59: '59s',
    60: '1m',
    61: '1m 1s',
    3599: '59m 59s',
    3600: '1h',
    3601: '1h 1s',
    3661: '1h 1m 1s',
    86400: '24h',
    90061: '25h 1m 1s',
    3600000: '1000h',
  };
  for (final entry in durations.entries) {
    test('exact stored duration ${entry.key} formats as ${entry.value}', () {
      expect(sessionDuration(entry.key), entry.value);
    });
  }
  test(
    'formatted breakdowns retain equality without rounding minute boundaries',
    () {
      int parse(String text) => RegExp(r'(\d+)([hms])')
          .allMatches(text)
          .fold<int>(
            0,
            (sum, m) =>
                sum + int.parse(m[1]!) * ({'h': 3600, 'm': 60, 's': 1}[m[2]]!),
          );
      for (final pair in [
        (61, 40),
        (120, 119),
        (3601, 3559),
        (90061, 31),
        (3, 0),
        (1, 1),
      ]) {
        final b = SessionBreakdown(fixture(pair.$1, pair.$2));
        expect(
          parse(sessionDuration(b.active!)) +
              parse(sessionDuration(b.inactive!)),
          parse(sessionDuration(b.total)),
        );
      }
      expect(sessionDuration(-1), 'Unknown');
    },
  );
  test(
    'unknown activity is never inferred from total or wall-clock elapsed time',
    () {
      final old = fixture(180, 0, unknown: true);
      final before = jsonEncode(old.toJson());
      final b = SessionBreakdown(old);
      expect(b.total, 180);
      expect(b.active, isNull);
      expect(b.inactive, isNull);
      expect(jsonEncode(old.toJson()), before);
      final broken = fixture(120, 60)..activeSeconds = 121;
      expect(SessionBreakdown(broken).known, false);
    },
  );
  test(
    'valid fully inactive sessions are distinct from incomplete history',
    () {
      final b = SessionBreakdown(fixture(120, 0));
      expect(b.active, 0);
      expect(b.inactive, 120);
      expect(SessionBreakdown(fixture(0, 0)).known, true);
    },
  );
  test('date range shows local dates across midnight and ongoing status', () {
    final s = fixture(90061, 31);
    expect(
      sessionRange(s),
      '2026-10-17 10:20:30 → 2026-10-18 11:21:31 · Local time',
    );
    expect(
      sessionRange(fixture(61, 40)),
      '2026-10-17 10:20:30 → 10:21:31 · Local time',
    );
    expect(
      sessionRange(fixture(0, 0, running: true)),
      'Started 2026-10-17 10:20:30 · Local time',
    );
  });
  for (final pair in [(61, 40), (120, 120), (120, 0), (0, 0), (90061, 1)]) {
    testWidgets('compact session row handles $pair', (tester) async {
      final s = fixture(pair.$1, pair.$2);
      final before = jsonEncode(s.toJson());
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SessionRow(session: s)),
          ),
        ),
      );
      expect(find.text('Total ${sessionDuration(pair.$1)}'), findsOneWidget);
      expect(find.text('Active ${sessionDuration(pair.$2)}'), findsOneWidget);
      expect(
        find.text('Inactive ${sessionDuration(pair.$1 - pair.$2)}'),
        findsOneWidget,
      );
      expect(find.text('Process ended'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.getSize(find.byType(SessionRow)).height, lessThan(150));
      expect(jsonEncode(s.toJson()), before);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
  testWidgets('unknown and running session rows have explicit status labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SessionRow(session: fixture(180, 0, unknown: true)),
              SessionRow(session: fixture(3, 3, running: true)),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Active Unknown'), findsOneWidget);
    expect(find.text('Inactive Unknown'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'session rows fit narrow layouts, large text and all theme presets',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final palette in [
          ...appearancePresets.values,
          (0xffabcdef, 0xff161821, 0xff232632),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: vaultTheme(
                brightness,
                palette.$1,
                background: palette.$2,
                surface: palette.$3,
              ),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        children: [
                          SessionRow(session: fixture(90061, 3601)),
                          SessionRow(session: fixture(120, 0, unknown: true)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets(
    'statistics mode changes labels and display values without changing records',
    (tester) async {
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() async {
        final c = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await c.initialize();
        return c;
      }))!;
      c.tracker.sessions.add(fixture(61, 40));
      final before = jsonEncode(c.tracker.toJson());
      for (final active in [true, false]) {
        c.settings = c.settings.copy(activityAdjusted: active);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ActivitySummary(controller: c)),
          ),
        );
        expect(
          find.text(active ? 'ACTIVE PLAYTIME' : 'TOTAL SESSION TIME'),
          findsOneWidget,
        );
        expect(find.text(active ? '40s' : '1m 1s'), findsWidgets);
        expect(c.settings.activityAdjusted, active);
        expect(jsonEncode(c.tracker.toJson()), before);
      }
      c.tracker.sessions.add(fixture(120, 0, unknown: true));
      c.settings = c.settings.copy(activityAdjusted: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ActivitySummary(controller: c)),
        ),
      );
      expect(find.text('Unknown'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'Activity handles long chart labels and unknown history without changing totals',
    (tester) async {
      tester.view.physicalSize = const Size(880, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() async {
        final c = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await c.initialize();
        return c;
      }))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Example game',
          installPath: 'x',
          libraryPath: 'x',
        ),
      ];
      final record = fixture(90061, 61);
      final today = dateKey(DateTime.now()),
          previous = dateKey(DateTime.now().subtract(const Duration(days: 1)));
      record.daily
        ..clear()
        ..addAll({previous: 86400, today: 3661});
      record.activeDaily
        ..clear()
        ..addAll({today: 61});
      c.tracker.sessions.add(record);
      final before = jsonEncode(c.tracker.toJson());
      for (final active in [true, false]) {
        c.settings = c.settings.copy(activityAdjusted: active);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                child: StatisticsPage(
                  key: ValueKey(active),
                  controller: c,
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byTooltip(active ? '1m 1s' : '24h'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Total 25h 1m 1s'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Inactive 25h'), findsOneWidget);
        expect(c.played(1), active ? 61 : 90061);
        expect(c.settings.activityAdjusted, active);
        expect(jsonEncode(c.tracker.toJson()), before);
        expect(tester.takeException(), isNull);
      }
      c.tracker.sessions.add(fixture(180, 0, unknown: true));
      c.settings = c.settings.copy(activityAdjusted: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatisticsPage(
              key: const ValueKey('unknown'),
              controller: c,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unknown'), findsWidgets);
      expect(
        find.text('Your first tracked session will appear here.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      final inactive = fixture(120, 0);
      inactive.daily
        ..clear()
        ..addAll({today: 120});
      c.tracker.sessions
        ..clear()
        ..add(inactive);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatisticsPage(
              key: const ValueKey('inactive'),
              controller: c,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('No active playtime recorded in the last seven days.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Your first tracked session will appear here.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'profile recent sessions show exact breakdown across profile sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(880, 620);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() async {
        final c = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await c.initialize();
        return c;
      }))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Example game',
          installPath: 'x',
          libraryPath: 'x',
        ),
      ];
      c.tracker.sessions.add(fixture(61, 40));
      final before = jsonEncode(c.tracker.toJson());
      for (final profile in ProfileSize.values) {
        c.settings = c.settings.copy(profileSize: profile);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DetailsPage(
                key: ValueKey(profile),
                controller: c,
                id: 1,
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.byType(SessionRow),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Total 1m 1s'), findsOneWidget);
        expect(find.text('Active 40s'), findsOneWidget);
        expect(find.text('Inactive 21s'), findsOneWidget);
        expect(
          tester.widget<SessionRow>(find.byType(SessionRow)).showTitle,
          false,
        );
        expect(jsonEncode(c.tracker.toJson()), before);
        expect(tester.takeException(), isNull);
      }
      c.tracker.sessions.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailsPage(
              key: const ValueKey('empty'),
              controller: c,
              id: 1,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text(
          'No recorded sessions yet. Keep GameVault open while playing.',
        ),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(SessionRow), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
}
