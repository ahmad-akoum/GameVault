import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/ui/theme.dart';
import 'package:gamevault/ui/theme_editor.dart';
import 'package:gamevault/ui/appearance_controls.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'services_test.dart' show TestMetadata, TestHltb;

class _ThemeController extends VaultController {
  _ThemeController(LocalStore store)
    : super(
        store: store,
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
  VaultSettings? saved;
  @override
  Future<void> setSettings(VaultSettings value) async {
    saved = value;
  }
}

void main() {
  for (final role in ['Background', 'Surface']) {
    testWidgets('reset, edit only $role, cancel and persist on Apply', (
      tester,
    ) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gv_theme_reset_'),
      ))!;
      final store = (await tester.runAsync(() async => LocalStore(dir)))!;
      const original = VaultSettings(
        background: 0xff112233,
        surface: 0xff334455,
      );
      await tester.runAsync(() => store.save([], original));
      final c = (await tester.runAsync(() async => _ThemeController(store)))!;
      await tester.runAsync(c.initialize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppearanceControls(controller: c),
            ),
          ),
        ),
      );

      Future<void> edit() async {
        await tester.tap(find.text('Theme studio'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Reset defaults'));
        await tester.tap(find.text('Reset defaults'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, role));
        await tester.tap(find.widgetWithText(ChoiceChip, role));
        await tester.pumpAndSettle();
        final hex = find.byType(TextField);
        await tester.ensureVisible(hex);
        await tester.enterText(hex, '445566');
        await tester.pumpAndSettle();
      }

      await edit();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.saved, isNull);
      final unchanged = (await tester.runAsync(store.load))!.settings;
      expect(unchanged.background, original.background);
      expect(unchanged.surface, original.surface);

      await edit();
      await tester.tap(find.text('Apply theme'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.save([], c.saved!));
      final reloaded = (await tester.runAsync(store.load))!.settings;
      expect(reloaded.background, role == 'Background' ? 0xff445566 : null);
      expect(reloaded.surface, role == 'Surface' ? 0xff445566 : null);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
    });
  }
  test('legacy theme and malformed gradient retain solid appearance', () {
    final old = VaultSettings.fromJson({'accent': 0xffaabbcc});
    expect(old.gradient, isNull);
    expect(old.accent, 0xffaabbcc);
    expect(
      VaultSettings.fromJson({
        'gradient': {
          'colors': [1],
        },
      }).gradient,
      isNull,
    );
  });

  testWidgets('theme draft applies multiple stops and survives serialization', (
    tester,
  ) async {
    VaultSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<VaultSettings>(
                  context: context,
                  builder: (_) => const ThemeEditor(settings: VaultSettings()),
                );
              },
              child: const Text('Edit theme'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit theme'));
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, 'Gradient backdrop');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add color'));
    await tester.tap(find.text('Add color'));
    await tester.pumpAndSettle();
    final hex = find.byType(TextField);
    await tester.ensureVisible(hex);
    await tester.enterText(hex, 'AB12EF');
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.tap(find.text('Apply theme'));
    await tester.pumpAndSettle();
    final loaded = VaultSettings.fromJson(saved!.toJson());
    expect(loaded.gradient!.colors.length, 3);
    expect(loaded.gradient!.colors.last, 0xffab12ef);
    for (final brightness in Brightness.values) {
      expect(
        vaultBackdrop(
          vaultTheme(brightness, loaded.accent),
          loaded.gradient,
        )!.colors.length,
        3,
      );
    }
  });
}
