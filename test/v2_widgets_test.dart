import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/components.dart';
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

void main() {
  for (final size in [
    const Size(880, 582),
    const Size(1280, 802),
    const Size(1920, 1042),
  ]) {
    testWidgets('V2 activity, collections and launch controls fit $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
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
          title:
              'A very long game title that should wrap without overflowing its layout',
          installPath: 'x',
          libraryPath: 'x',
        ),
      ];
      await tester.pumpWidget(GameVaultApp(controller: c, manageWindow: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bar_chart_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Your activity'), findsOneWidget);
      expect(
        find.text('Your first tracked session will appear here.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.folder_outlined));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('New collection'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Weekend');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(c.settings.collections, ['Weekend']);
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(GameTile)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Play game'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Session time 0s  •  Active 0s'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Your progress'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '25');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(c.games.single.progressPercent, 25);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    });
  }
}
