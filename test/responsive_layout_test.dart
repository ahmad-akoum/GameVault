import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/library_pages.dart';
import 'package:gamevault/ui/collections_page.dart';
import 'package:gamevault/ui/detected_page.dart';
import 'package:gamevault/ui/details_page.dart';
import 'package:gamevault/ui/settings_page.dart';
import 'package:gamevault/ui/activity_pages.dart';
import 'package:gamevault/ui/artwork_manager.dart';
import 'package:gamevault/ui/artwork_viewer.dart';
import 'package:gamevault/ui/theme.dart';
import 'session_presentation_test.dart' show fixture;
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

void main() {
  for (final width in [360.0, 400.0, 480.0, 600.0, 880.0, 1280.0]) {
    testWidgets('all pages and artwork controls remain reachable at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 620);
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
      c.settings = c.settings.copy(
        paths: [r'D:\Long SteamLibrary\steamapps\common\Example'],
        collections: ['Weekend'],
      );
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Example game with a long edition title',
          installPath: r'D:\SteamLibrary\steamapps\common\Example',
          libraryPath: r'D:\SteamLibrary',
          hltb: const HltbEntry(
            id: 1,
            title: 'Example',
            main: 1234.5,
            extras: 2000,
            complete: 3000,
          ),
          hltbState: HltbState.ambiguous,
          candidates: const [
            HltbEntry(
              id: 1,
              title: 'A long alternative edition game title',
              main: 32,
            ),
          ],
        ),
      ];
      c.detected = [
        const SteamGame(
          appId: 2,
          name: 'Another long detected game title',
          installPath: 'x',
          libraryPath: r'D:\SteamLibrary',
        ),
      ];
      c.tracker.sessions.add(fixture(90061, 3601));
      final before = jsonEncode(c.tracker.toJson());
      Future<void> page(Widget widget, String last) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: vaultTheme(
              width == 400 ? Brightness.light : Brightness.dark,
              0xff78aaff,
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 620),
                textScaler: TextScaler.linear(width == 400 ? 1.3 : 1),
              ),
              child: Scaffold(
                body: Padding(padding: const EdgeInsets.all(12), child: widget),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$widget initial $width',
        );
        for (var i = 0; find.text(last).evaluate().isEmpty && i < 100; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -180),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text(last), findsWidgets, reason: '$widget target $last');
        await tester.ensureVisible(find.text(last).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$widget scrolled $width',
        );
      }

      await page(
        HomePage(
          controller: c,
          onOpen: (_) {},
          onScan: () {},
          onLibrary: (_) {},
        ),
        'Recently added',
      );
      await page(
        LibraryPage(controller: c, onOpen: (_) {}, onScan: () {}),
        c.games.single.title,
      );
      await page(
        CollectionsPage(controller: c, onOpen: (_) {}),
        c.games.single.title,
      );
      await page(
        DetectedPage(controller: c, onSettings: () {}, onLibrary: () {}),
        'Add selected games',
      );
      if (width == 880) {
        c.detected = List.generate(
          30,
          (i) => SteamGame(
            appId: 100 + i,
            name: 'Detected result $i',
            installPath: 'x',
            libraryPath: 'x',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DetectedPage(
                key: const ValueKey('many'),
                controller: c,
                onSettings: () {},
                onLibrary: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Detected result 29'),
          250,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
          maxScrolls: 100,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Detected result 29'));
        await tester.pumpAndSettle();
        expect(find.text('Detected result 29').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (final size in ProfileSize.values) {
        c.settings = c.settings.copy(profileSize: size);
        await page(
          DetailsPage(key: ValueKey(size), controller: c, id: 1, onBack: () {}),
          'Remove from GameVault',
        );
      }
      await page(
        StatisticsPage(controller: c, onOpen: (_) {}),
        'Process ended',
      );
      await page(
        SettingsPage(controller: c, onScan: () {}),
        'A personal Windows game library. Steam and HowLongToBeat are independent services.',
      );
      // Color picker must remain usable in a narrow dialog too.
      await tester.scrollUntilVisible(
        find.text('Custom Accent'),
        -180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.ensureVisible(find.text('Custom Accent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom Accent'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ArtworkManager(controller: c, id: 1),
                ),
                child: const Text('Manage'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Profile banner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile banner'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Restore Default'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Apply banner').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        const MaterialApp(
          home: ArtworkViewer(title: 'A long title for artwork preview'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Close artwork').hitTestable(), findsOneWidget);
      expect(jsonEncode(c.tracker.toJson()), before);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    });
  }
  testWidgets(
    'narrow navigation drawer gives every destination access, with titlebar overlay',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 620);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
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
      await tester.pumpWidget(GameVaultApp(controller: c));
      await tester.pumpAndSettle();
      for (final label in [
        'My Library',
        'Favorites',
        'Collections',
        'Activity',
        'Settings',
        'Home',
      ]) {
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(label).last,
          100,
          scrollable: find
              .descendant(
                of: find.byType(Drawer),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(find.byType(Drawer).hitTestable(), findsNothing);
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
}
