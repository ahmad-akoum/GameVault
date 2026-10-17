import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/artwork_store.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/metadata_provider.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/session_tracker.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/artwork_manager.dart';
import 'package:gamevault/ui/appearance_controls.dart';
import 'package:gamevault/ui/theme.dart';
import 'services_test.dart' show fixtureDirectory, TestHltb;

class RefreshArtwork implements GameMetadataProvider {
  Completer<void>? gate;
  @override
  Future<VaultGame> enrich(VaultGame game) async {
    if (gate != null) await gate!.future;
    return game.copy(
      coverPath: 'new-cover.jpg',
      heroPath: 'new-hero.jpg',
      developer: 'Updated developer',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List red, blue;
  Future<Uint8List> png(Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(const Rect.fromLTWH(0, 0, 48, 72), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(48, 72);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    return bytes;
  }

  setUpAll(() async {
    red = await png(Colors.red);
    blue = await png(Colors.blue);
  });
  Future<VaultController> controller(
    Directory dir, [
    RefreshArtwork? metadata,
  ]) async {
    final c = VaultController(
      store: LocalStore(dir),
      scanner: SteamScanner(installationRoots: () async => []),
      metadata: metadata ?? RefreshArtwork(),
      hltb: TestHltb(),
    );
    await c.initialize();
    return c;
  }

  VaultGame game({String? cover, String? hero}) => VaultGame(
    appId: 1,
    title: 'Fixture',
    installPath: 'install',
    libraryPath: 'library',
    coverPath: cover,
    heroPath: hero,
    favorite: true,
    developer: 'Original developer',
    collections: ['Keep'],
    progressPercent: 42,
  );

  test(
    'imports validate pixels, copy original bytes and survive source deletion',
    () async {
      final dir = await fixtureDirectory();
      try {
        final source = await File(
          p.join(dir.path, 'source.png'),
        ).writeAsBytes(red);
        final store = ArtworkStore(Directory(p.join(dir.path, 'artwork')));
        final managed = await store.importImage(source.path, 1, true);
        expect(await File(managed).readAsBytes(), red);
        await source.delete();
        await store.validate(managed);
        for (final name in ['bad.png', 'unsupported.svg', 'noextension']) {
          final invalid = await File(
            p.join(dir.path, name),
          ).writeAsString('not an image');
          await expectLater(
            store.importImage(invalid.path, 1, true),
            throwsA(isA<ArtworkFailure>()),
          );
        }
        await expectLater(
          store.validate(p.join(dir.path, 'missing.png')),
          throwsA(isA<ArtworkFailure>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'legacy selections migrate; cover/banner save, restore and travel independently',
    () async {
      final dir = await fixtureDirectory();
      final c = await controller(dir);
      try {
        final art = Directory(p.join(dir.path, 'artwork'));
        await art.create();
        final original = await File(
          p.join(art.path, 'original.png'),
        ).writeAsBytes(red);
        final custom = await File(
          p.join(art.path, 'custom.png'),
        ).writeAsBytes(blue);
        c.games = [game(cover: original.path, hero: original.path)];
        final initial = c.games.single.toJson();
        final now = DateTime.utc(2026, 10, 17);
        c.tracker.sample(
          now: now,
          monotonicSeconds: 0,
          games: [
            GameObservation(1, 'Fixture', {'a'}, true),
          ],
          idleSeconds: 0,
        );
        c.tracker.sample(
          now: now.add(const Duration(seconds: 2)),
          monotonicSeconds: 2,
          games: [
            GameObservation(1, 'Fixture', {'a'}, true),
          ],
          idleSeconds: 0,
        );
        final sessions = jsonEncode(c.tracker.toJson());
        expect(
          await c.applyArtwork(
            1,
            cover: true,
            path: custom.path,
            contained: true,
          ),
          true,
        );
        expect(c.game(1)!.heroPath, original.path);
        expect(c.game(1)!.artwork!.originalCover, original.path);
        expect(
          await c.applyArtwork(
            1,
            cover: false,
            path: custom.path,
            contained: false,
          ),
          true,
        );
        expect(c.game(1)!.coverPath, custom.path);
        expect(c.game(1)!.artwork!.coverContained, true);
        await c.scan();
        expect(c.game(1)!.coverPath, custom.path);
        expect(c.game(1)!.heroPath, custom.path);
        var loaded = (await c.store.load()).games.single;
        expect(loaded.coverPath, custom.path);
        expect(loaded.heroPath, custom.path);
        expect(loaded.artwork!.originalHero, original.path);
        expect(loaded.artwork!.covers, [custom.path]);
        final raw = jsonDecode(await c.store.file.readAsString())['games'][0];
        expect(p.isAbsolute(raw['artwork']['originalCover']), false);
        expect(p.isAbsolute(raw['artwork']['covers'][0]), false);
        await c.applyArtwork(
          1,
          cover: true,
          path: loaded.artwork!.originalCover,
          contained: false,
        );
        expect(c.game(1)!.coverPath, original.path);
        expect(c.game(1)!.heroPath, custom.path);
        await c.applyArtwork(
          1,
          cover: false,
          path: loaded.artwork!.originalHero,
          contained: false,
        );
        final after = c.game(1)!.toJson()..remove('artwork');
        initial.remove('artwork');
        expect(after, initial);
        expect(jsonEncode(c.tracker.toJson()), sessions);
        loaded = (await c.store.load()).games.single;
        expect(loaded.heroPath, original.path);
        final moved = await fixtureDirectory();
        try {
          await File(
            p.join(moved.path, 'vault.json'),
          ).writeAsString(await c.store.file.readAsString());
          final movedGame = (await LocalStore(moved).load()).games.single;
          expect(
            movedGame.artwork!.originalCover,
            p.join(moved.path, 'artwork', 'original.png'),
          );
        } finally {
          await moved.delete(recursive: true);
        }
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'metadata refresh including an in-flight refresh preserves user selection',
    () async {
      final dir = await fixtureDirectory();
      final metadata = RefreshArtwork();
      final c = await controller(dir, metadata);
      try {
        c.games = [game(cover: 'original.jpg', hero: 'banner.jpg')];
        metadata.gate = Completer<void>();
        final refresh = c.refreshMetadata(1);
        await Future<void>.delayed(Duration.zero);
        await c.applyArtwork(
          1,
          cover: true,
          path: 'custom.jpg',
          contained: true,
        );
        metadata.gate!.complete();
        await refresh;
        expect(c.game(1)!.coverPath, 'custom.jpg');
        expect(c.game(1)!.heroPath, 'banner.jpg');
        expect(c.game(1)!.artwork!.originalCover, 'original.jpg');
        expect(c.game(1)!.developer, 'Updated developer');
        c.games = [game()];
        await c.refreshMetadata(1);
        expect(c.game(1)!.coverPath, 'new-cover.jpg');
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'cover-only legacy banner fallback stays independent after a cover change',
    () async {
      final dir = await fixtureDirectory();
      final c = await controller(dir);
      try {
        c.games = [game(cover: 'original.jpg')];
        expect(c.game(1)!.profileArtworkPath, 'original.jpg');
        await c.applyArtwork(1, cover: true, path: 'new.jpg', contained: false);
        expect(c.game(1)!.profileArtworkPath, 'original.jpg');
        expect(c.game(1)!.coverPath, 'new.jpg');
        c.games = [game()];
        await c.applyArtwork(
          1,
          cover: true,
          path: 'custom.jpg',
          contained: false,
        );
        expect(c.game(1)!.profileArtworkPath, isNull);
        await c.applyArtwork(1, cover: true, path: null, contained: false);
        expect(c.game(1)!.coverPath, isNull);
        await c.refreshMetadata(1);
        expect(c.game(1)!.coverPath, isNull);
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'metadata cache refresh cannot overwrite original artwork files',
    () async {
      final dir = await fixtureDirectory();
      try {
        final cover = await File(
          p.join(dir.path, '1_cover.jpg'),
        ).writeAsString('preserve existing bytes');
        final hero = await File(
          p.join(dir.path, '1_hero.jpg'),
        ).writeAsString('also preserve');
        final client = MockClient(
          (r) async => r.url.host == 'store.steampowered.com'
              ? http.Response(
                  jsonEncode({
                    '1': {
                      'success': true,
                      'data': {'name': 'Fixture'},
                    },
                  }),
                  200,
                )
              : http.Response.bytes(
                  red,
                  200,
                  headers: {'content-type': 'image/jpeg'},
                ),
        );
        await SteamMetadataProvider(
          dir,
          client: client,
        ).enrich(game(cover: cover.path, hero: hero.path));
        expect(await cover.readAsString(), 'preserve existing bytes');
        expect(await hero.readAsString(), 'also preserve');
        client.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('failed persistence preserves selected artwork', () async {
    final dir = await fixtureDirectory();
    final c = await controller(dir);
    try {
      c.games = [game(cover: 'original.jpg')];
      await Directory('${c.store.file.path}.pending').create();
      expect(
        await c.applyArtwork(
          1,
          cover: true,
          path: 'custom.jpg',
          contained: false,
        ),
        false,
      );
      expect(c.game(1)!.coverPath, 'original.jpg');
      expect(c.game(1)!.artwork, isNull);
    } finally {
      await c.shutdown();
      c.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'Steam choices validate, deduplicate and reuse cache; unavailable is not fabricated',
    () async {
      final dir = await fixtureDirectory();
      var requests = 0;
      try {
        final current = await File(
          p.join(dir.path, 'selected.png'),
        ).writeAsBytes(red);
        final store = ArtworkStore(Directory(p.join(dir.path, 'artwork')));
        final client = MockClient((r) async {
          requests++;
          return http.Response.bytes(
            r.url.path.contains('header') ? blue : red,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        });
        final choices = await store.steamChoices(1, true, [
          current.path,
        ], client: client);
        expect(choices.length, 1);
        expect(requests, 2);
        expect(
          await store.steamChoices(1, true, [
            current.path,
            ...choices,
          ], client: client),
          isEmpty,
        );
        expect(requests, 2);
        expect(await store.steamChoices(-1, true, [], client: client), isEmpty);
        final absent = MockClient(
          (r) async => http.Response('Unavailable', 404),
        );
        expect(await store.steamChoices(2, true, [], client: absent), isEmpty);
        final corrupt = MockClient(
          (r) async => http.Response(
            'invalid image',
            200,
            headers: {'content-type': 'image/jpeg'},
          ),
        );
        expect(await store.steamChoices(3, true, [], client: corrupt), isEmpty);
        client.close();
        absent.close();
        corrupt.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'legacy titlebar placement reproduces missing Overlay assertion',
    (tester) async {
      final errors = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: const Scaffold(),
            builder: (context, child) => Column(
              children: [
                const Tooltip(message: 'Window action', child: Text('Action')),
                Expanded(child: child!),
              ],
            ),
          ),
        );
      } finally {
        FlutterError.onError = previous;
      }
      expect(
        errors.any((e) => e.toString().contains('No Overlay widget found')),
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('desktop window tooltips have an Overlay and can be shown', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          ),
    );
    tester.view.physicalSize = const Size(1280, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(fixtureDirectory))!;
    final c = (await tester.runAsync(() => controller(dir)))!;
    await tester.pumpWidget(GameVaultApp(controller: c));
    await tester.pumpAndSettle();
    final tooltip = find.byTooltip('Minimize');
    expect(Overlay.maybeOf(tester.element(tooltip)), isNotNull);
    tester.state<TooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await c.shutdown();
      c.dispose();
      await dir.delete(recursive: true);
    });
  });
  testWidgets(
    'Apply commits previewed cover; Cancel discards a pending default restore',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(fixtureDirectory))!;
      final c = (await tester.runAsync(() => controller(dir)))!;
      final original = (await tester.runAsync(
        () => File(p.join(dir.path, 'original.png')).writeAsBytes(red),
      ))!;
      final alternate = (await tester.runAsync(
        () => File(p.join(dir.path, 'alternate.png')).writeAsBytes(blue),
      ))!;
      c.games = [
        game(cover: original.path, hero: original.path).copy(
          artwork: ArtworkPreferences(
            originalCover: original.path,
            originalHero: original.path,
            covers: [alternate.path],
          ),
        ),
      ];
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
      await tester.ensureVisible(find.text('Saved artwork'));
      await tester.tap(find.text('Saved artwork'));
      await tester.pumpAndSettle();
      expect(c.game(1)!.coverPath, original.path);
      final saved = (await tester.runAsync(() async => Completer<void>()))!;
      void observe() {
        if (c.game(1)!.coverPath == alternate.path && !saved.isCompleted) {
          saved.complete();
        }
      }

      c.addListener(observe);
      await tester.runAsync(() async {
        await tester.tap(find.text('Apply cover'));
        await saved.future.timeout(const Duration(seconds: 5));
      });
      c.removeListener(observe);
      await tester.pumpAndSettle();
      expect(c.game(1)!.coverPath, alternate.path);
      expect(c.game(1)!.heroPath, original.path);
      await tester.ensureVisible(find.text('Restore Default'));
      await tester.tap(find.text('Restore Default'));
      await tester.pumpAndSettle();
      expect(c.game(1)!.coverPath, alternate.path);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.game(1)!.coverPath, alternate.path);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pump();
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        // Retain this tiny generated fixture in ignored build/test_data.
        // Windows codecs can hold mapped images until the test isolate exits;
        // deleting those files here is not part of the behavior being tested.
      });
    },
  );
  for (final size in [const Size(880, 620), const Size(1280, 840)]) {
    testWidgets(
      'artwork manager independent preview and cancellation fit $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = (await tester.runAsync(fixtureDirectory))!;
        final c = (await tester.runAsync(() => controller(dir)))!;
        final file = (await tester.runAsync(
          () => File(p.join(dir.path, 'cover.png')).writeAsBytes(red),
        ))!;
        final alternate = (await tester.runAsync(
          () => File(p.join(dir.path, 'alternate.png')).writeAsBytes(blue),
        ))!;
        c.games = [
          game(cover: file.path, hero: file.path).copy(
            artwork: ArtworkPreferences(
              originalCover: file.path,
              originalHero: file.path,
              covers: [alternate.path],
            ),
          ),
        ];
        final before = jsonEncode(c.game(1)!.toJson());
        for (final brightness in Brightness.values) {
          for (final preset in [
            ...appearancePresets.values,
            (0xffabcdef, 0xff0e121d, 0xff191d2a),
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: vaultTheme(
                  brightness,
                  preset.$1,
                  background: preset.$2,
                  surface: preset.$3,
                ),
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
            expect(find.text('Current cover'), findsOneWidget);
            expect(find.text('Current banner'), findsOneWidget);
            await tester.tap(find.text('Profile banner'));
            await tester.pumpAndSettle();
            expect(find.text('Apply banner'), findsOneWidget);
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            expect(jsonEncode(c.game(1)!.toJson()), before);
            expect(tester.takeException(), isNull);
          }
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
}
