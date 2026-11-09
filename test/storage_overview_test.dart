import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/installed_storage.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/storage_overview_page.dart';
import 'services_test.dart' show TestMetadata, TestHltb;

class _StorageController extends VaultController {
  _StorageController()
    : super(
        store: LocalStore(Directory.systemTemp),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );

  final measurement = Completer<InstalledStorage>();
  final refreshed = <int>[];
  Map<int, InstalledStorage>? fixture;
  Map<int, InstalledStorage>? refreshFixture;

  @override
  Future<InstalledStorage> overviewStorage(
    VaultGame game, {
    required bool refresh,
  }) async {
    if (refresh && refreshFixture != null) {
      refreshed.add(game.appId);
      return refreshFixture![game.appId]!;
    }
    if (fixture != null) return fixture![game.appId]!;
    if (refresh) {
      refreshed.add(game.appId);
      return measurement.future;
    }
    return InstalledStorage(game.installPath, 1 << 30, DateTime.utc(2026));
  }
}

void main() {
  testWidgets('a negative or relocated result stays with its own App ID', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _StorageController();
    addTearDown(c.dispose);
    const shared = 'D:/Games/Shared';
    final now = DateTime.utc(2026);
    final bytes = InstalledStorage(shared, 1 << 30, now);
    c.games = [
      for (final id in [1, 2, 3])
        VaultGame(
          appId: id,
          title: 'Fixture $id',
          installPath: shared,
          libraryPath: 'D:/Games',
        ),
    ];
    c.fixture = {1: bytes, 2: bytes, 3: bytes};
    c.refreshFixture = {
      1: InstalledStorage('', null, now, notInstalled: true),
      2: bytes,
      3: bytes,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageOverviewPage(controller: c, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh sizes'));
    await tester.pumpAndSettle();
    expect(c.refreshed, [1, 2]); // Share the positive measurement with game 3.
    expect(find.text('No installed size'), findsOneWidget);
    expect(find.text('1.00 GB'), findsNWidgets(3)); // One total, two cards.

    c.refreshed.clear();
    c.refreshFixture![1] = InstalledStorage('E:/Moved', 2 << 30, now);
    await tester.tap(find.text('Refresh sizes'));
    await tester.pumpAndSettle();
    expect(c.refreshed, [1, 2]);
    expect(find.text('3.00 GB'), findsOneWidget);
    expect(find.text('No installed size'), findsNothing);
  });
  testWidgets(
    'verified uninstalled games have their own group until reinstalled',
    (tester) async {
      final c = _StorageController();
      addTearDown(c.dispose);
      final now = DateTime.utc(2026);
      const path = 'D:/Games/Fixture';
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Fixture',
          installPath: path,
          libraryPath: 'D:/Games',
        ),
      ];
      c.fixture = {1: InstalledStorage('', null, now, notInstalled: true)};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageOverviewPage(controller: c, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not Installed'), findsOneWidget);
      expect(find.text('No installed size'), findsOneWidget);
      expect(find.text('0 measured · 0 stale · 0 unavailable'), findsOneWidget);
      expect(find.text('Location unavailable'), findsNothing);

      c.fixture![1] = InstalledStorage(path, 1 << 30, now);
      await tester.tap(find.text('Refresh sizes'));
      await tester.pumpAndSettle();
      expect(find.text('Not Installed'), findsNothing);
      expect(find.text('1 measured · 0 stale · 0 unavailable'), findsOneWidget);
      expect(find.text('1.00 GB'), findsNWidgets(2));
    },
  );
  test('tracked sizes count shared and nested folders once, across drives', () {
    InstalledStorage size(String path, int? bytes) =>
        InstalledStorage(path, bytes, DateTime.utc(2026));
    expect(
      trackedStorageBytes([
        size(r'd:\Games\Shared\Child', 20),
        size(r'D:\Games\Shared\', 50),
        size(r'd:/games/shared', 50),
        size(r'D:\Games\Shared2', 15),
        size(r'E:\Games\Shared', 10),
        size(r'E:\Unavailable', null),
        size(r'C:\Games', null),
        size(r'C:\Games\VerifiedChild', 5),
      ]),
      80,
    );
  });

  testWidgets(
    'cached sizes need no scan and cancel stops the remaining queue',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 620);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _StorageController();
      addTearDown(c.dispose);
      c.games = [
        for (var i = 1; i <= 2; i++)
          VaultGame(
            appId: i,
            title: 'Fixture $i',
            installPath: 'D:/Games/$i',
            libraryPath: 'D:/Games',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageOverviewPage(controller: c, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.00 GB'), findsOneWidget);
      expect(c.refreshed, isEmpty);
      await tester.tap(find.text('Refresh sizes'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      c.measurement.complete(
        InstalledStorage('D:/Games/1', 3 << 30, DateTime.utc(2026)),
      );
      await tester.pumpAndSettle();
      expect(c.refreshed, [1]);
      expect(find.text('4.00 GB'), findsOneWidget);
      expect(
        find.text('Refresh cancelled. Completed results are retained.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
