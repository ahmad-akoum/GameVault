import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/components.dart';
import 'package:gamevault/ui/collections_page.dart';
import 'package:gamevault/ui/details_page.dart';
import 'services_test.dart' show fixtureDirectory, TestMetadata, TestHltb;

class _CollectionStore extends LocalStore {
  _CollectionStore() : super(Directory.systemTemp);

  List<VaultGame>? saved;

  @override
  Future<void> save(
    List<VaultGame> games,
    VaultSettings settings, {
    List<Map<String, dynamic>> sessions = const [],
  }) async {
    saved = games;
  }
}

void main() {
  testWidgets('Collections page edits membership without changing other data', (
    tester,
  ) async {
    final store = _CollectionStore();
    final c = VaultController(
      store: store,
      scanner: SteamScanner(installationRoots: () async => []),
      metadata: TestMetadata(),
      hltb: TestHltb(),
    );
    addTearDown(c.dispose);
    c.settings = const VaultSettings(collections: ['Favorites list', 'Other']);
    c.games = [
      VaultGame(
        appId: 1,
        title: 'Fixture',
        installPath: 'x',
        libraryPath: 'x',
        favorite: true,
        collections: const ['Other'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => CollectionsPage(controller: c, onOpen: (_) {}),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Favorites list'));
    await tester.pumpAndSettle();
    Future<void> toggleMembership() async {
      await tester.tap(find.text('Manage games'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Fixture'));
      await tester.pumpAndSettle();
    }

    await toggleMembership();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(c.games.single.collections, ['Other']);

    await toggleMembership();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.saved!.single.collections, ['Other', 'Favorites list']);
    expect(c.games.single.favorite, isTrue);
    expect(find.text('Fixture'), findsWidgets);

    await toggleMembership();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.saved!.single.collections, ['Other']);
    expect(find.text('Fixture'), findsNothing);
  });

  testWidgets(
    'saved HLTB estimates stay visible with search and refresh available',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 3000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final hltb = TestHltb();
      final c = (await tester.runAsync(() async {
        final controller = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: hltb,
        );
        controller.games = [
          VaultGame(
            appId: 1,
            title: 'Saved game',
            installPath: 'x',
            libraryPath: 'x',
            hltbState: HltbState.matched,
            hltb: const HltbEntry(id: 42, title: 'Saved HLTB title', main: 8),
            candidates: const [HltbEntry(id: 43, title: 'Saved alternative')],
          ),
        ];
        return controller;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailsPage(controller: c, id: 1, onBack: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Collections'), findsNothing);
      expect(
        find.text('Game Settings / Installation / Tracking'),
        findsOneWidget,
      );
      expect(find.text('Main Story'), findsOneWidget);
      expect(
        find.textContaining('Source: HowLongToBeat • Saved HLTB title'),
        findsOneWidget,
      );
      expect(find.text('Refresh'), findsOneWidget);
      expect(
        find.text('Find or change the HowLongToBeat match'),
        findsOneWidget,
      );
      expect(hltb.searchedTitles, isEmpty);
      await tester.tap(find.text('Find or change the HowLongToBeat match'));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Saved alternative'), findsOneWidget);
      expect(find.text('Use this match'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

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
        find.text('Play Game'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(DetailsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Playtime Overview'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Your progress'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
      c.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    });
  }
}
