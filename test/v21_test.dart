import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/appearance_controls.dart';
import 'package:gamevault/ui/artwork_viewer.dart';
import 'package:gamevault/ui/app_version.dart';
import 'package:gamevault/ui/details_page.dart';
import 'package:gamevault/ui/settings_page.dart';
import 'package:gamevault/ui/theme.dart';
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

class IdlePlatform implements GamePlatform {
  @override
  Future<void> launch(VaultGame game) async {}
  @override
  Future<WindowsSample> sample(List<VaultGame> games) async =>
      WindowsSample([], 300);
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test('old settings migrate without changing prior preferences', () {
    final s = VaultSettings.fromJson({
      'accent': 0xffabcdef,
      'theme': 'light',
      'idleThreshold': 90,
      'focusGrace': 15,
    });
    expect(s.accent, 0xffabcdef);
    expect(s.profileSize, ProfileSize.comfortable);
    expect(s.background, isNull);
    expect(s.surface, isNull);
    expect(s.idleThreshold, 90);
    expect(s.focusGrace, 15);
    final bad = VaultSettings.fromJson({
      'profileSize': 'unknown',
      'background': 'bad',
      'surface': -1,
    });
    expect(bad.profileSize, ProfileSize.comfortable);
    expect(bad.background, isNull);
    expect(bad.surface, isNull);
  });
  test(
    'custom settings survive store close and reopen independently',
    () async {
      final dir = await fixtureDirectory();
      final store = LocalStore(dir);
      await store.acquireLock();
      final s = const VaultSettings().copy(
        accent: 0xff445566,
        background: 0xff121218,
        surface: 0xff242434,
        profileSize: ProfileSize.expanded,
      );
      await store.save([], s);
      await store.close();
      final reopened = LocalStore(dir);
      await reopened.acquireLock();
      final loaded = (await reopened.load()).settings;
      expect(loaded.toJson(), s.toJson());
      expect(loaded.copy(accent: 0xff999999).surface, s.surface);
      expect(loaded.copy(resetColors: true).background, isNull);
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );
  test('idle monitoring does not trigger whole-app rebuilds', () async {
    final dir = await fixtureDirectory();
    final c = VaultController(
      store: LocalStore(dir),
      scanner: SteamScanner(installationRoots: () async => []),
      metadata: TestMetadata(),
      hltb: TestHltb(),
      platform: IdlePlatform(),
    );
    await c.initialize();
    var notifications = 0;
    c.addListener(() => notifications++);
    await c.pollGames();
    await c.pollGames();
    expect(notifications, 0);
    await c.shutdown();
    c.dispose();
    await dir.delete(recursive: true);
  });
  test(
    'presets and extreme custom hues retain text contrast in both modes',
    () {
      for (final brightness in Brightness.values) {
        for (final colors in [
          ...appearancePresets.values,
          (0xff000000, 0xffffffff, 0xffff0000),
          (0xffffffff, 0xff000000, 0xff00ff00),
        ]) {
          final s = vaultTheme(
            brightness,
            colors.$1,
            background: colors.$2,
            surface: colors.$3,
          ).colorScheme;
          for (final surface in [
            s.surface,
            s.surfaceContainer,
            s.surfaceContainerHighest,
          ]) {
            expect(contrast(s.onSurface, surface), greaterThanOrEqualTo(4.5));
            expect(
              contrast(s.onSurfaceVariant, surface),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(contrast(s.primary, s.surface), greaterThanOrEqualTo(4.5));
          expect(
            contrast(s.primary, s.surfaceContainer),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrast(s.primary, s.onPrimary), greaterThanOrEqualTo(4.5));
        }
      }
    },
  );
  testWidgets('version label uses native package build metadata', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('gamevault/windows'),
          (call) async => '2.1.0+3',
        );
    await tester.pumpWidget(const MaterialApp(home: AppVersionLabel()));
    await tester.pumpAndSettle();
    expect(find.text('GameVault 2.1.0'), findsOneWidget);
    expect(find.textContaining('+3'), findsNothing);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('gamevault/windows'),
          null,
        );
  });
  for (final size in [
    const Size(880, 582),
    const Size(1280, 802),
    const Size(1920, 1042),
  ]) {
    testWidgets('all profile sizes and artwork controls fit $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = VaultController(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      await tester.runAsync(c.initialize);
      c.games = [
        VaultGame(
          appId: 1,
          title: 'A long example game title for responsive layout',
          installPath: 'x',
          libraryPath: 'x',
        ),
      ];
      for (final profile in ProfileSize.values) {
        c.settings = c.settings.copy(profileSize: profile);
        await tester.pumpWidget(
          MaterialApp(
            theme: vaultTheme(Brightness.dark, c.settings.accent),
            home: Scaffold(
              body: DetailsPage(controller: c, id: 1, onBack: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final art = find.byKey(const ValueKey('profileArtwork'));
        expect(tester.getSize(art).height, switch (profile) {
          ProfileSize.compact => 180,
          ProfileSize.comfortable => 260,
          ProfileSize.expanded => 420,
        });
        await tester.tap(find.byTooltip('Enlarge artwork'));
        await tester.pumpAndSettle();
        expect(find.byType(ArtworkViewer), findsOneWidget);
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          greaterThan(1),
        );
        await tester.tap(find.byTooltip('Zoom out'));
        await tester.pump();
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1, .01),
        );
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.tap(find.byTooltip('Reset zoom'));
        await tester.pump();
        expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ArtworkViewer), findsNothing);
        expect(find.byType(DetailsPage), findsOneWidget);
        await tester.tap(find.byTooltip('Enlarge artwork'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close artwork'));
        await tester.pumpAndSettle();
        expect(find.byType(ArtworkViewer), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(GameVaultApp(controller: c, manageWindow: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Cobalt'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Cobalt'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Cobalt'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      expect(c.settings.background, appearancePresets['Cobalt']!.$2);
      await tester.scrollUntilVisible(
        find.text('Custom Background'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Custom Background'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom Background'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ABCDEF');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.settings.background, appearancePresets['Cobalt']!.$2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    });
  }
}
