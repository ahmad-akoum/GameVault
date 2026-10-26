import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_updates.dart';
import 'package:gamevault/services/windows_startup.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/artwork_manager.dart';
import 'package:gamevault/ui/library_pages.dart';
import 'package:gamevault/ui/settings_page.dart';
import 'package:gamevault/ui/detected_page.dart';
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

Future<void> waitUntil(bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed.inSeconds >= 5) {
      throw TimeoutException('Fixture action did not complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<VaultController> controller(Directory dir) async {
  final c = VaultController(
    store: LocalStore(dir),
    scanner: SteamScanner(installationRoots: () async => []),
    metadata: TestMetadata(),
    hltb: TestHltb(),
    startup: WindowsStartup(allowed: false),
  );
  await c.initialize();
  return c;
}

Future<File> image(Directory dir, String name, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  final picture = recorder.endRecording();
  final pixels = await picture.toImage(4, 4);
  final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
  pixels.dispose();
  picture.dispose();
  return File(p.join(dir.path, name)).writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets(
    'Epic discovery row identifies its launcher rather than displaying a negative Steam ID',
    (tester) async {
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() => controller(dir)))!;
      c.detected = [
        SteamGame(
          appId: -1,
          name: 'Epic fixture',
          installPath: dir.path,
          libraryPath: dir.path,
          source: GameSource.epic,
          epic: const EpicIdentity('sandbox', 'catalog', 'app'),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetectedPage(
              controller: c,
              onSettings: () {},
              onLibrary: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Epic Games (experimental)'), findsOneWidget);
      expect(find.textContaining('Steam -1'), findsNothing);
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
    'artwork reuse previews and saves independently in both directions without duplicate image files',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() => controller(dir)))!;
      final cover = (await tester.runAsync(
        () => image(dir, 'cover.png', Colors.red),
      ))!;
      final banner = (await tester.runAsync(
        () => image(dir, 'banner.png', Colors.blue),
      ))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Fixture',
          installPath: dir.path,
          libraryPath: dir.path,
          coverPath: cover.path,
          heroPath: banner.path,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ArtworkManager(controller: c, id: 1)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use profile banner'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Use profile banner'));
        final dynamic state = tester.state(find.byType(ArtworkManager));
        await waitUntil(() => state.busy == false);
      });
      await tester.pumpAndSettle();
      expect(c.game(1)!.coverPath, cover.path);
      expect(find.textContaining('Preview ready.'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Apply cover'));
        await waitUntil(() => c.game(1)!.coverPath == banner.path);
      });
      await tester.pumpAndSettle();
      expect(c.game(1)!.heroPath, banner.path);
      await tester.ensureVisible(find.text('Restore Default'));
      await tester.tap(find.text('Restore Default'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Apply cover'));
        await waitUntil(() => c.game(1)!.coverPath == cover.path);
      });
      await tester.pumpAndSettle();
      expect(c.game(1)!.heroPath, banner.path);
      await tester.ensureVisible(find.text('Profile banner'));
      await tester.tap(find.text('Profile banner'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use library cover'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Use library cover'));
        final dynamic state = tester.state(find.byType(ArtworkManager));
        await waitUntil(() => state.busy == false);
      });
      await tester.pumpAndSettle();
      expect(c.game(1)!.heroPath, banner.path);
      await tester.runAsync(() async {
        await tester.tap(find.text('Apply banner'));
        await waitUntil(() => c.game(1)!.heroPath == cover.path);
      });
      await tester.pumpAndSettle();
      final snapshot = (await tester.runAsync(c.store.load))!;
      expect(snapshot.games.single.heroPath, cover.path);
      expect(snapshot.games.single.artwork!.originalHero, banner.path);
      expect(
        (await tester.runAsync(
          () => dir.list().where((e) => e.path.endsWith('.png')).length,
        )),
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
      });
    },
  );
  testWidgets(
    'sidebar manual collapse persists and responsive drawer preserves navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() => controller(dir)))!;
      await tester.pumpWidget(GameVaultApp(controller: c, manageWindow: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('LOCAL LIBRARY'), findsNothing);
      expect(find.text('V2'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Collapse navigation'));
        await waitUntil(() => c.settings.sidebarCollapsed);
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand navigation'), findsOneWidget);
      expect(find.byTooltip('My Library'), findsOneWidget);
      final snapshot = (await tester.runAsync(c.store.load))!;
      expect(snapshot.settings.sidebarCollapsed, true);
      for (final width in [1049.0, 600.0]) {
        tester.view.physicalSize = Size(width, 840);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sidebarToggle')), findsNothing);
        expect(c.settings.sidebarCollapsed, true);
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(360, 700);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open navigation'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      expect(find.text('My Library'), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebarToggle')), findsNothing);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1050, 840);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand navigation'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Expand navigation'));
        await waitUntil(() => !c.settings.sidebarCollapsed);
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collapse navigation'), findsOneWidget);
      expect(
        (await tester.runAsync(c.store.load))!.settings.sidebarCollapsed,
        false,
      );
      tester.view.physicalSize = const Size(1049, 840);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebarToggle')), findsNothing);
      tester.view.physicalSize = const Size(1280, 840);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collapse navigation'), findsOneWidget);
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
    'library menus expose new options and update filter follows refreshed evidence',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() => controller(dir)))!;
      c.games = [
        for (final id in [1, 2])
          VaultGame(
            appId: id,
            title: 'Fixture $id',
            installPath: dir.path,
            libraryPath: dir.path,
          ),
      ];
      c.steamUpdates[1] = const SteamUpdateEvidence(
        SteamUpdateState.downloading,
        'fixture',
      );
      Widget page() => MaterialApp(
        home: Scaffold(
          body: LibraryPage(controller: c, onOpen: (_) {}, onScan: () {}),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('libraryStatus')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Needs Update').last);
      await tester.pumpAndSettle();
      expect(find.text('Fixture 1'), findsWidgets);
      expect(find.text('Fixture 2'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('librarySort')));
      await tester.pumpAndSettle();
      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Least Recently Played'), findsOneWidget);
      await tester.tap(find.text('Least Recently Played'));
      await tester.pumpAndSettle();
      c.steamUpdates[1] = const SteamUpdateEvidence(
        SteamUpdateState.noUpdateRecorded,
        'complete',
      );
      // A parent rebuild is the same signal as the controller's normal update notification.
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Fixture 1'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
  for (final width in [360.0, 800.0, 1280.0]) {
    testWidgets(
      'General startup setting is disabled in a candidate and fits width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = (await tester.runAsync(fixtureDirectory))!;
        final c = (await tester.runAsync(() => controller(dir)))!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsPage(controller: c, onScan: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = tester.widget<SwitchListTile>(
          find.byType(SwitchListTile).first,
        );
        expect(toggle.value, false);
        expect(toggle.onChanged, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await c.shutdown();
          c.dispose();
          await dir.delete(recursive: true);
        });
      },
    );
  }
}
