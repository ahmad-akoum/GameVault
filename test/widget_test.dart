import 'package:gamevault/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'services_test.dart' show TestMetadata, TestHltb, fixtureDirectory;

void main() {
  testWidgets(
    'Finished includes completionist games and search narrows the view',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 840);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() async {
        final value = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await value.initialize();
        return value;
      }))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Completed game',
          installPath: 'a',
          libraryPath: 'a',
          status: GameStatus.completed,
        ),
        VaultGame(
          appId: 2,
          title: 'Completionist game',
          installPath: 'b',
          libraryPath: 'b',
          status: GameStatus.completionist,
        ),
      ];
      await tester.pumpWidget(GameVaultApp(controller: c, manageWindow: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      expect(find.text('Completed game'), findsWidgets);
      expect(find.text('Completionist game'), findsWidgets);
      await tester.enterText(find.byType(TextField).first, 'Completionist');
      await tester.pumpAndSettle();
      expect(find.text('Completed game'), findsNothing);
      expect(find.text('Completionist game'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
  testWidgets('small artwork fallback has no overflow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 48,
            height: 70,
            child: GameArtwork(title: 'Unavailable artwork'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(1280, 840),
    const Size(880, 620),
    const Size(2560, 1440),
  ]) {
    testWidgets('empty UI and settings render at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() async {
        final value = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await value.initialize();
        return value;
      }))!;
      await tester.pumpWidget(GameVaultApp(controller: c, manageWindow: false));
      await tester.pumpAndSettle();
      expect(find.text('A library that’s yours'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('Light'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(c.settings.theme, AppearanceMode.light);
      expect(
        (await tester.runAsync(c.store.load))!.settings.theme,
        AppearanceMode.light,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    });
  }
  testWidgets(
    'populated library, status filters, details and confirmation dialog',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(880, 620);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() async {
        final value = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await value.initialize();
        return value;
      }))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'A very long example game title for layout verification',
          installPath: 'D:\\SteamLibrary\\steamapps\\common\\game',
          libraryPath: 'D:\\SteamLibrary',
          status: GameStatus.playing,
          hltbState: HltbState.matched,
          hltb: const HltbEntry(
            id: 1,
            title: 'Example',
            main: 10,
            extras: 15,
            complete: 20,
          ),
        ),
      ];
      await tester.pumpWidget(GameVaultApp(controller: c, manageWindow: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tapAt(tester.getCenter(find.byType(GameTile)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('HOW LONG TO BEAT'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('HOW LONG TO BEAT'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Remove from GameVault'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from GameVault'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from GameVault?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.games.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
