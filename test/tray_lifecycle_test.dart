import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/session_tracker.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'services_test.dart' show TestMetadata, TestHltb;

class _Controller extends VaultController {
  _Controller(Directory dir)
    : super(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
  final gate = Completer<void>();
  int exits = 0;
  @override
  Future<void> shutdown() async {
    exits++;
    await gate.future;
    tracker.closeAll('Test exit');
  }
}

void main() {
  retryRegression();
  test('new installations opt in and old settings retain close behavior', () {
    expect(const VaultSettings().closeToTray, isTrue);
    expect(VaultSettings.fromJson({}).closeToTray, isFalse);
    expect(
      VaultSettings.fromJson(const VaultSettings().toJson()).closeToTray,
      isTrue,
    );
  });

  testWidgets(
    'close keeps a session open; tray Exit awaits shutdown exactly once',
    (tester) async {
      const tray = MethodChannel('gamevault/tray');
      const window = MethodChannel('window_manager');
      final messenger = tester.binding.defaultBinaryMessenger;
      int hides = 0, destroys = 0;
      messenger.setMockMethodCallHandler(tray, (call) async {
        hides++;
        return true;
      });
      messenger.setMockMethodCallHandler(window, (call) async {
        if (call.method == 'destroy') destroys++;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(tray, null);
        messenger.setMockMethodCallHandler(window, null);
      });
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gv_tray_test_'),
      ))!;
      final c = _Controller(dir);
      await tester.runAsync(c.initialize);
      void sample(int time) => c.tracker.sample(
        now: DateTime.utc(2026).add(Duration(seconds: time)),
        monotonicSeconds: time,
        games: [
          GameObservation(11, 'Fixture', {'process'}, true),
        ],
        idleSeconds: 0,
      );
      sample(0);
      await tester.pumpWidget(GameVaultApp(controller: c));
      Future<void> event(MethodChannel channel, MethodCall call) async {
        final done = Completer<void>();
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(call),
          (_) => done.complete(),
        );
        await done.future;
      }

      await event(window, const MethodCall('onEvent', {'eventName': 'close'}));
      await tester.pump();
      expect(hides, 1);
      expect(c.exits, 0);
      sample(2);
      expect(c.tracker.sessions.single.activeSeconds, 2);
      expect(c.tracker.sessions.single.open, isTrue);
      final exit = event(tray, const MethodCall('exit'));
      final secondExit = event(tray, const MethodCall('exit'));
      await tester.pump();
      expect(c.exits, 1);
      expect(destroys, 0);
      c.gate.complete();
      await Future.wait([exit, secondExit]);
      expect(destroys, 1);
      expect(c.tracker.sessions.single.activeSeconds, 2);
      expect(c.tracker.sessions.single.open, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.store.close);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}

class _RetryStore extends LocalStore {
  _RetryStore(super.directory);

  bool fail = true;
  bool closed = false;
  List<Map<String, dynamic>>? savedSessions;

  @override
  Future<void> save(
    List<VaultGame> games,
    VaultSettings settings, {
    List<Map<String, dynamic>> sessions = const [],
  }) async {
    if (fail) throw const StorageFailure('Fixture disk is full');
    savedSessions = sessions;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void retryRegression() {
  testWidgets('tray Exit reopens the window and retries the final save', (
    tester,
  ) async {
    const tray = MethodChannel('gamevault/tray');
    const window = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];

    messenger.setMockMethodCallHandler(window, (call) async {
      calls.add(call.method);
      if (call.method == 'isMinimized') return false;

      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(window, null));

    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('gv_exit_retry_'),
    ))!;
    final store = _RetryStore(dir);
    final c = VaultController(
      store: store,
      scanner: SteamScanner(installationRoots: () async => []),
      metadata: TestMetadata(),
      hltb: TestHltb(),
    );
    for (final seconds in [0, 2]) {
      c.tracker.sample(
        now: DateTime.utc(2026).add(Duration(seconds: seconds)),
        monotonicSeconds: seconds,
        games: [
          GameObservation(11, 'Fixture', {'process'}, true),
        ],
        idleSeconds: 0,
      );
    }
    await tester.pumpWidget(GameVaultApp(controller: c));
    {
      final done = Completer<void>();
      await messenger.handlePlatformMessage(
        tray.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('exit')),
        (_) => done.complete(),
      );
      await done.future;
    }
    await tester.pumpAndSettle();
    expect(calls, contains('show'));
    expect(calls, isNot(contains('destroy')));
    expect(store.closed, isFalse);
    expect(find.text('Fixture disk is full'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.text('Retry Save and Exit'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'destroy'), hasLength(1));
    expect(store.closed, isTrue);
    expect(store.savedSessions, c.tracker.toJson());
    expect(c.tracker.sessions.single.activeSeconds, 2);
    expect(c.tracker.sessions.single.open, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
