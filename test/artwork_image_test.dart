import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/ui/artwork_image.dart';
import 'package:gamevault/ui/components.dart';

void main() {
  test('provider identity follows source and decode geometry', () {
    const source = NetworkImage('https://example.invalid/cover');
    const a = ArtworkImage(source, 256, 384, BoxFit.cover);
    const b = ArtworkImage(source, 256, 384, BoxFit.cover);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const ArtworkImage(source, 512, 768, BoxFit.cover)));
    expect(a, isNot(const ArtworkImage(source, 256, 384, BoxFit.contain)));
    expect(
      a,
      isNot(
        const ArtworkImage(
          NetworkImage('https://example.invalid/hero'),
          256,
          384,
          BoxFit.cover,
        ),
      ),
    );
  });
  test('landscape covers retain height needed for portrait cropping', () {
    final size = artworkDecodeSize(460, 215, 256, 384, BoxFit.cover);
    expect(size.width, 460);
    expect(size.height, 215);
  });
  test('expanded banner decode follows cropped height, preserves ratio', () {
    final size = artworkDecodeSize(1920, 620, 896, 448, BoxFit.cover);
    expect(size.height, 448);
    expect(size.width, 1388);
  });
  test('high DPI never decodes beyond original resolution', () {
    final size = artworkDecodeSize(1920, 620, 1792, 896, BoxFit.cover);
    expect(size.width, 1920);
    expect(size.height, 620);
  });
  test('portrait cover and contained images downsample appropriately', () {
    final size = artworkDecodeSize(600, 900, 256, 384, BoxFit.cover);
    expect(size.width, 256);
    expect(size.height, 384);
    final contained = artworkDecodeSize(1920, 620, 896, 448, BoxFit.contain);
    expect(contained.width, 896);
    expect(contained.height, 290);
    expect(artworkBucket(221), artworkBucket(240));
  });
  testWidgets('decoder uses intrinsic dimensions and reuses cached key', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1920, 620), Paint());
    final picture = recorder.endRecording();
    final original = (await tester.runAsync(() => picture.toImage(1920, 620)))!;
    final bytes = (await tester.runAsync(
      () => original.toByteData(format: ui.ImageByteFormat.png),
    ))!.buffer.asUint8List();
    final source = MemoryImage(bytes);
    final provider = ArtworkImage(source, 896, 448, BoxFit.cover);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    expect(
      key,
      await ArtworkImage(
        source,
        896,
        448,
        BoxFit.cover,
      ).obtainKey(ImageConfiguration.empty),
    );
    await tester.pumpWidget(MaterialApp(home: Image(image: provider)));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final rendered = tester.widget<RawImage>(find.byType(RawImage));
    expect(rendered.image!.width, 1388);
    expect(rendered.image!.height, 448);
    // A running game's timer rebuilds the parent every two seconds. Check the
    // rendered frame itself, before asynchronous key lookup can refill it.
    for (var tick = 0; tick < 4; tick++) {
      ui.Image? frameImage;
      tester.binding.addPostFrameCallback((_) {
        frameImage = tester.widget<RawImage>(find.byType(RawImage)).image;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Image(image: ArtworkImage(source, 896, 448, BoxFit.cover)),
        ),
      );
      expect(
        frameImage,
        isNotNull,
        reason: 'Unchanged artwork must survive tracker tick $tick',
      );
    }
    final cached = ArtworkImage(
      source,
      896,
      448,
      BoxFit.cover,
    ).resolve(ImageConfiguration.empty);
    expect(
      cached.completer,
      isNotNull,
      reason: 'Cached source resolution must remain synchronous',
    );
    original.dispose();
    picture.dispose();
  });
  testWidgets('fullscreen bypasses resizing and preserves chosen source', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GameArtwork(
            url: 'https://example.invalid/selected-hero',
            title: 'Art',
            fullResolution: true,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect(
      (image.image as NetworkImage).url,
      'https://example.invalid/selected-hero',
    );
    expect(image.fit, BoxFit.contain);
    await tester.pumpAndSettle();
  });
}
