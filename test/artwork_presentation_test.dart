import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/artwork_presentation.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/artwork_image.dart';
import 'package:gamevault/ui/artwork_manager.dart';
import 'package:gamevault/ui/components.dart';
import 'services_test.dart' show TestMetadata, TestHltb;
import 'playtime_reconciliation_test.dart' show session;

Future<Uint8List> bands(int width, int height) async {
  final recorder = ui.PictureRecorder(), vertical = height >= width;
  final canvas = Canvas(recorder);
  for (var i = 0; i < 3; i++) {
    canvas.drawRect(
      vertical
          ? Rect.fromLTWH(0, height * i / 3, width.toDouble(), height / 3)
          : Rect.fromLTWH(width * i / 3, 0, width / 3, height.toDouble()),
      Paint()..color = [Colors.red, Colors.green, Colors.blue][i],
    );
  }
  final picture = recorder.endRecording(),
      image = await picture.toImage(width, height);
  final data = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(
    () async =>
        dir = await Directory.systemTemp.createTemp('gamevault_art_position_'),
  );
  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    expect(dir.path.startsWith(Directory.systemTemp.path), true);
    await dir.delete(recursive: true);
  });

  test(
    'legacy fit values retain their appearance; malformed new values are bounded',
    () {
      final old = ArtworkPreferences.fromJson({'coverContained': true});
      expect(old.coverDisplay.mode, ArtworkFit.contain);
      expect(old.heroDisplay.mode, ArtworkFit.crop);
      final parsed = ArtworkPresentation.fromJson({
        'mode': 'unknown',
        'x': 99,
        'y': double.nan,
        'zoom': -2,
      });
      expect(parsed.mode, ArtworkFit.crop);
      expect(parsed.x, 1);
      expect(parsed.y, 0);
      expect(parsed.zoom, 1);
      final roundtrip = ArtworkPresentation.fromJson(
        jsonDecode(
          jsonEncode(
            const ArtworkPresentation(
              mode: ArtworkFit.blurred,
              x: .5,
              y: -.5,
              zoom: 2,
            ).toJson(),
          ),
        ),
      );
      expect(roundtrip.mode, ArtworkFit.blurred);
      expect(roundtrip.zoom, 2);
    },
  );

  test(
    'independent slot positions persist through restart and metadata refresh; source/session data unchanged',
    () async {
      final c = VaultController(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      await c.initialize();
      final art = await File(
        '${dir.path}/source.png',
      ).writeAsBytes(await bands(40, 400));
      final original = await art.readAsBytes();
      c.games = [
        VaultGame(
          appId: 11,
          title: 'Synthetic',
          installPath: 'fixture',
          libraryPath: 'fixture',
          coverPath: art.path,
          heroPath: art.path,
        ),
      ];
      c.tracker.sessions.add(session(3600, 1800));
      final before = jsonEncode(c.tracker.toJson());
      await c.applyArtwork(
        11,
        cover: true,
        path: art.path,
        contained: false,
        presentation: const ArtworkPresentation(x: .7, y: -.6, zoom: 2.4),
      );
      await c.applyArtwork(
        11,
        cover: false,
        path: art.path,
        contained: false,
        presentation: const ArtworkPresentation(mode: ArtworkFit.blurred),
      );
      await c.refreshMetadata(11);
      final restored = (await c.store.load()).games.single.artwork!;
      expect(restored.coverDisplay.x, .7);
      expect(restored.coverDisplay.y, -.6);
      expect(restored.coverDisplay.zoom, 2.4);
      expect(restored.heroDisplay.mode, ArtworkFit.blurred);
      expect(c.game(11)!.artwork!.originalHero, art.path);
      await c.applyArtwork(
        11,
        cover: false,
        path: art.path,
        contained: false,
        presentation: const ArtworkPresentation(),
      );
      expect(c.game(11)!.artwork!.coverDisplay.zoom, 2.4);
      expect(c.game(11)!.artwork!.heroDisplay.mode, ArtworkFit.crop);
      expect(jsonEncode(c.tracker.toJson()), before);
      expect(await art.readAsBytes(), original);
      await c.shutdown();
    },
  );

  Future<void> decoded(WidgetTester tester) async {
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final frames = tester.widgetList<RawImage>(find.byType(RawImage));
      if (frames.isNotEmpty && frames.every((r) => r.image != null)) return;
    }
    fail('Artwork did not decode');
  }

  for (final size in [(40, 400), (400, 40), (100, 100)]) {
    for (final mode in ArtworkFit.values) {
      testWidgets(
        '${size.$1}x${size.$2} $mode renders without distortion, blank rebuilds or overflow',
        (tester) async {
          final file = (await tester.runAsync(
            () async => File(
              '${dir.path}/source.png',
            ).writeAsBytes(await bands(size.$1, size.$2)),
          ))!;
          Widget content() => MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 100,
                child: GameArtwork(
                  path: file.path,
                  title: 'Test',
                  presentation: ArtworkPresentation(
                    mode: mode,
                    x: .5,
                    y: -.5,
                    zoom: 2,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(content());
          await decoded(tester);
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          expect(images.length, mode == ArtworkFit.blurred ? 2 : 1);
          if (mode == ArtworkFit.blurred) {
            final background = tester
                .widgetList<RawImage>(find.byType(RawImage))
                .first;
            expect(background.image!.width, lessThanOrEqualTo(256));
            expect(background.image!.height, lessThanOrEqualTo(256));
            expect(images.last.fit, BoxFit.contain);
            expect(find.byType(ImageFiltered), findsOneWidget);
          }
          if (mode == ArtworkFit.crop) {
            expect(images.single.alignment, const Alignment(.5, -.5));
            final provider = images.single.image as ArtworkImage;
            expect(provider.width, greaterThanOrEqualTo(600));
            expect(provider.height, greaterThanOrEqualTo(200));
          }
          for (var i = 0; i < 3; i++) {
            await tester.pumpWidget(content());
            expect(
              tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .every((r) => r.image != null),
              true,
              reason: 'Tracking rebuild must preserve decoded frames',
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'crop position selects real source regions, including zoomed axes',
    (tester) async {
      final file = (await tester.runAsync(
        () async =>
            File('${dir.path}/source.png').writeAsBytes(await bands(100, 300)),
      ))!;
      final key = GlobalKey();
      for (final y in [-1.0, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: GameArtwork(
                    path: file.path,
                    title: 'Test',
                    presentation: ArtworkPresentation(y: y, zoom: 2),
                  ),
                ),
              ),
            ),
          ),
        );
        await decoded(tester);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final pixels = (await tester.runAsync(() => image.toByteData()))!;
        final offset = (50 * image.width + 50) * 4;
        expect(pixels.getUint8(offset + (y < 0 ? 0 : 2)), greaterThan(180));
        image.dispose();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Apply saves banner positioning across reload while Cancel discards the next draft',
    (tester) async {
      await tester.runAsync(() async {
        final c = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await c.initialize();
        final image = await File(
          '${dir.path}/source.png',
        ).writeAsBytes(await bands(40, 400));
        final before = await image.readAsBytes();
        c.games = [
          VaultGame(
            appId: 11,
            title: 'Synthetic',
            installPath: 'fixture',
            libraryPath: 'fixture',
            coverPath: image.path,
            heroPath: image.path,
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ArtworkManager(controller: c, id: 11),
                  ),
                  child: const Text('Manage'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Profile banner'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('Zoom')));
        await tester.drag(
          find.byKey(const ValueKey('Zoom')),
          const Offset(60, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply banner'));
        for (var i = 0; i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (c.game(11)!.artwork != null &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        expect(c.game(11)!.artwork, isNotNull);
        final zoom = c.game(11)!.artwork!.heroDisplay.zoom;
        expect(zoom, greaterThan(1));
        final restored = (await c.store.load()).games.single;
        expect(restored.artwork!.heroDisplay.zoom, zoom);
        expect(restored.artwork!.coverDisplay.zoom, 1);
        await tester.ensureVisible(find.text('Fit with blurred background'));
        await tester.tap(find.text('Fit with blurred background'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(c.game(11)!.artwork!.heroDisplay.mode, ArtworkFit.crop);
        expect(
          (await c.store.load()).games.single.artwork!.heroDisplay.zoom,
          zoom,
        );
        expect(await image.readAsBytes(), before);
        await tester.pumpWidget(const SizedBox());
        await c.shutdown();
      });
    },
  );
  testWidgets(
    'manager previews positioning and blurred fit; Cancel preserves both slots at narrow width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
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
          appId: 11,
          title: 'Synthetic',
          installPath: 'fixture',
          libraryPath: 'fixture',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ArtworkManager(controller: c, id: 11),
                ),
                child: const Text('Manage'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('Zoom')));
      await tester.drag(
        find.byKey(const ValueKey('Zoom')),
        const Offset(70, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<GameArtwork>(find.byType(GameArtwork))
            .any((a) => (a.presentation?.zoom ?? 1) > 1),
        true,
      );
      await tester.ensureVisible(find.text('Fit with blurred background'));
      await tester.tap(find.text('Fit with blurred background'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(
        tester
            .widgetList<GameArtwork>(find.byType(GameArtwork))
            .any((a) => a.presentation?.mode == ArtworkFit.blurred),
        true,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkManager), findsNothing);
      expect(c.game(11)!.artwork, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(c.shutdown);
    },
  );
}
