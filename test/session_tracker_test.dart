import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/models/play_session.dart';
import 'package:gamevault/services/session_tracker.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

void main() {
  late SessionTracker tracker;
  final origin = DateTime.utc(2026, 10, 13, 12);
  void tick(
    int seconds, {
    bool focused = true,
    int idle = 0,
    Set<String> processes = const {'1:creation'},
    int grace = 10,
    int threshold = 60,
  }) {
    tracker.sample(
      now: origin.add(Duration(seconds: seconds)),
      monotonicSeconds: seconds,
      games: [GameObservation(1, 'Game', processes, focused)],
      idleSeconds: idle,
      focusGrace: grace,
      idleThreshold: threshold,
    );
  }

  setUp(() => tracker = SessionTracker());
  test('60 second idle cutoff resumes without losing full duration', () {
    tick(0);
    for (var i = 2; i <= 70; i += 2) {
      tick(i, idle: i);
    }
    expect(tracker.total(1), 70);
    expect(tracker.total(1, active: true), 60);
    tick(72, idle: 0);
    expect(tracker.total(1, active: true), 62);
  });
  for (final threshold in [30, 60, 120, 300, 600]) {
    test(
      'focused keyboard/controller idle stops at configured $threshold seconds',
      () {
        tick(0, threshold: threshold);
        for (var i = 2; i <= threshold + 20; i += 2) {
          tick(i, idle: i, threshold: threshold);
        }
        expect(tracker.total(1), threshold + 20);
        expect(tracker.total(1, active: true), threshold);
        tick(threshold + 22, idle: 0, threshold: threshold);
        tick(threshold + 24, idle: 2, threshold: threshold);
        expect(tracker.total(1), threshold + 24);
        expect(tracker.total(1, active: true), threshold + 4);
        final s = tracker.sessions.single;
        expect(s.daily.values.fold(0, (a, b) => a + b), s.seconds);
        expect(s.activeDaily.values.fold(0, (a, b) => a + b), s.activeSeconds);
        tracker.closeAll('test');
        final restored = SessionTracker()
          ..load(jsonDecode(jsonEncode(tracker.toJson())) as List);
        expect(restored.total(1), tracker.total(1));
        expect(restored.total(1, active: true), tracker.total(1, active: true));
      },
    );
  }
  test('controller input while alt-tabbed cannot bypass focus grace', () {
    tick(0);
    for (var i = 2; i <= 40; i += 2) {
      tick(i, focused: false, idle: 0);
    }
    expect(tracker.total(1), 40);
    expect(tracker.total(1, active: true), 10);
    tick(42, focused: true, idle: 90);
    expect(tracker.total(1, active: true), 10);
    tick(44, focused: true, idle: 0);
    expect(tracker.total(1, active: true), 12);
  });
  test('focus grace is ten seconds and regaining focus resumes', () {
    tick(0);
    for (var i = 2; i <= 20; i += 2) {
      tick(i, focused: false);
    }
    expect(tracker.total(1), 20);
    expect(tracker.total(1, active: true), 10);
    tick(22);
    expect(tracker.total(1, active: true), 12);
  });
  test('zero focus grace stops immediately', () {
    tick(0);
    tick(2, focused: false, grace: 0);
    expect(tracker.total(1, active: true), 0);
  });
  test('multiple processes share one session and PID reuse starts another', () {
    tick(0, processes: {'1:a', '2:b'});
    tick(2, processes: {'2:b', '3:c'});
    expect(tracker.sessions.length, 1);
    expect(tracker.total(1), 2);
    tick(4, processes: {'2:new'});
    expect(tracker.sessions.length, 2);
    expect(tracker.total(1), 2);
    tick(6, processes: {});
    expect(tracker.current(1), isNull);
  });
  test(
    'duplicate samples, backward clocks and suspend cannot inflate time',
    () {
      tick(0);
      tick(2);
      tick(2);
      tick(1);
      tick(200);
      expect(tracker.total(1), 2);
      expect(tracker.sessions.first.reason, 'Monitoring gap');
    },
  );
  test('recovery closes at last checkpoint and never counts downtime', () {
    tick(0);
    tick(2);
    tick(4);
    final persisted = jsonDecode(jsonEncode(tracker.toJson())) as List;
    tracker = SessionTracker()..load(persisted);
    expect(tracker.current(1), isNull);
    expect(tracker.total(1), 4);
    expect(
      tracker.sessions.single.endedAt,
      origin.add(const Duration(seconds: 4)),
    );
    tick(500);
    expect(tracker.total(1), 4);
  });
  test('daily totals split across local midnight and equal session totals', () {
    final time = DateTime(2026, 10, 13, 23, 59, 58);
    tracker.sample(
      now: time,
      monotonicSeconds: 0,
      games: [
        GameObservation(1, 'Game', {'a'}, true),
      ],
      idleSeconds: 0,
    );
    tracker.sample(
      now: time.add(const Duration(seconds: 4)),
      monotonicSeconds: 4,
      games: [
        GameObservation(1, 'Game', {'a'}, true),
      ],
      idleSeconds: 0,
    );
    expect(tracker.sessions.single.daily, {'2026-10-13': 2, '2026-10-14': 2});
    expect(tracker.sessions.single.activeDaily, tracker.sessions.single.daily);
  });
  test(
    'V1 migration preserves fields and keeps a permanent recovery copy',
    () async {
      final dir = await fixtureDirectory();
      final store = LocalStore(dir);
      try {
        final game = VaultGame(
          appId: 1,
          title: 'Preserved',
          installPath: 'x',
          libraryPath: 'x',
          favorite: true,
          status: GameStatus.onHold,
        );
        final old = jsonEncode({
          'version': 1,
          'games': [game.toJson()],
          'settings': const VaultSettings().toJson(),
        });
        await store.file.writeAsString(old);
        final loaded = await store.load();
        expect(loaded.games.single.favorite, true);
        expect(loaded.settings.idleThreshold, 60);
        expect(loaded.sessions, isEmpty);
        tick(0);
        tick(2);
        await store.save(
          loaded.games,
          loaded.settings,
          sessions: tracker.toJson(),
        );
        expect(await File('${store.file.path}.v1-backup').readAsString(), old);
        final migrated = await store.load();
        expect(migrated.games.single.status, GameStatus.onHold);
        expect(migrated.sessions.length, 1);
        expect(jsonDecode(await store.file.readAsString())['version'], 2);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'collection rename/delete preserves games and rejects duplicate names',
    () async {
      final dir = await fixtureDirectory();
      final c = VaultController(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      try {
        await c.initialize();
        c.games = [
          VaultGame(
            appId: 1,
            title: 'Game',
            installPath: 'x',
            libraryPath: 'x',
          ),
        ];
        await c.saveCollection('Adventures');
        await c.update(1, (g) => g.copy(collections: ['Adventures']));
        await c.saveCollection('adventures');
        expect(c.settings.collections.length, 1);
        await c.saveCollection('Weekend', previous: 'Adventures');
        expect(c.games.single.collections, ['Weekend']);
        await c.deleteCollection('Weekend');
        expect(c.games.length, 1);
        expect(c.games.single.collections, isEmpty);
        expect((await c.store.load()).games.length, 1);
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'manual executable import requires an existing path and deduplicates',
    () async {
      final dir = await fixtureDirectory();
      final c = VaultController(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      try {
        await c.initialize();
        await c.addManual('Missing', '${dir.path}/missing.exe');
        expect(c.games, isEmpty);
        final exe = await File('${dir.path}/fixture.exe').writeAsBytes([0]);
        await c.addManual('Local game', exe.path);
        await c.addManual('Duplicate', exe.path);
        expect(c.games.length, 1);
        expect(c.games.single.isManual, true);
        expect((await c.store.load()).games.single.executablePath, isNotNull);
        final previousId = c.games.single.appId;
        final now = DateTime.now();
        c.tracker.sample(
          now: now,
          monotonicSeconds: 0,
          games: [
            GameObservation(previousId, 'Local game', {'fixture'}, true),
          ],
          idleSeconds: 0,
        );
        c.tracker.closeAll('Fixture stopped');
        await c.remove(previousId);
        await c.addManual('Another game', exe.path);
        expect(c.games.single.appId, lessThan(previousId));
        expect(c.played(c.games.single.appId), 0);
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('invalid session durations are not trusted', () {
    final j = PlaySession(
      id: 's',
      gameId: 1,
      title: 'G',
      startedAt: origin,
      lastObservedAt: origin,
    ).toJson();
    j['activeSeconds'] = 5;
    expect(() => PlaySession.fromJson(j), throwsFormatException);
  });
  test(
    'damaged V2 sessions recover without replacing the good backup',
    () async {
      final dir = await fixtureDirectory();
      final store = LocalStore(dir);
      try {
        await store.acquireLock();
        final session = PlaySession(
          id: 'saved',
          gameId: 1,
          title: 'Game',
          startedAt: origin,
          lastObservedAt: origin,
          endedAt: origin,
        ).toJson();
        await store.save([], const VaultSettings(), sessions: [session]);
        await store.save([], const VaultSettings(), sessions: [session]);
        final goodBackup = await store.backup.readAsString();
        final damaged = jsonDecode(await store.file.readAsString());
        damaged['sessions'][0]['endedAt'] = 'not a date';
        await store.file.writeAsString(jsonEncode(damaged));
        final recovered = await store.load();
        expect(recovered.recovered, true);
        expect(recovered.sessions.single['id'], 'saved');
        await store.save([], const VaultSettings(), sessions: [session]);
        expect(await store.backup.readAsString(), goodBackup);
        final duplicate = jsonDecode(await store.file.readAsString());
        duplicate['sessions'].add(session);
        await store.file.writeAsString(jsonEncode(duplicate));
        expect((await store.load()).recovered, true);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
