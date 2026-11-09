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

  @override
  Future<InstalledStorage> overviewStorage(
    VaultGame game, {
    required bool refresh,
  }) async {
    if (refresh) {
      refreshed.add(game.appId);
      return measurement.future;
    }
    return InstalledStorage(game.installPath, 1 << 30, DateTime.utc(2026));
  }
}

void main() {
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
