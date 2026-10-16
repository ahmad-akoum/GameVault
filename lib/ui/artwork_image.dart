import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// Buckets physical display dimensions to reuse decodes during small resizes.
int artworkBucket(double value) => (value / 64).ceil() * 64;

/// Preserve enough pixels for the cropped axis, without inventing source detail.
ui.TargetImageSize artworkDecodeSize(
  int width,
  int height,
  int targetWidth,
  int targetHeight,
  BoxFit fit,
) {
  final fitted = applyBoxFit(
    fit,
    Size(width.toDouble(), height.toDouble()),
    Size(targetWidth.toDouble(), targetHeight.toDouble()),
  );
  final scale = math.min(
    1.0,
    math.max(
      fitted.destination.width / fitted.source.width,
      fitted.destination.height / fitted.source.height,
    ),
  );
  return ui.TargetImageSize(
    width: math.max(1, (width * scale).ceil()),
    height: math.max(1, (height * scale).ceil()),
  );
}

typedef ArtworkImageKey = ({Object source, int width, int height, BoxFit fit});

/// Uses intrinsic dimensions supplied by the decoder; no synchronous file probes.
class ArtworkImage extends ImageProvider<ArtworkImageKey> {
  const ArtworkImage(this.source, this.width, this.height, this.fit);
  final ImageProvider source;
  final int width, height;
  final BoxFit fit;

  @override
  bool operator ==(Object other) =>
      other is ArtworkImage &&
      source == other.source &&
      width == other.width &&
      height == other.height &&
      fit == other.fit;

  @override
  int get hashCode => Object.hash(source, width, height, fit);

  @override
  Future<ArtworkImageKey> obtainKey(ImageConfiguration configuration) {
    // FileImage/MemoryImage/NetworkImage return SynchronousFuture keys.
    // Preserve that timing: an async wrapper would briefly replace a cached
    // stream with an unresolved stream on dependency-driven resolutions.
    return source
        .obtainKey(configuration)
        .then<ArtworkImageKey>(
          (key) => (source: key, width: width, height: height, fit: fit),
        );
  }

  @override
  ImageStreamCompleter loadImage(
    ArtworkImageKey key,
    ImageDecoderCallback decode,
  ) {
    final completer = source.loadImage(
      key.source,
      (buffer, {getTargetSize}) => decode(
        buffer,
        getTargetSize: (w, h) =>
            artworkDecodeSize(w, h, key.width, key.height, key.fit),
      ),
    );
    completer.addEphemeralErrorListener((error, stack) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }
}
