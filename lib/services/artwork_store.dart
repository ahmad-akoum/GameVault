import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ArtworkFailure implements Exception {
  const ArtworkFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ArtworkStore {
  ArtworkStore(this.directory);
  final Directory directory;
  static const maxBytes = 16 * 1024 * 1024;
  static const extensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];

  Future<void> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ArtworkFailure(
        'This image is missing. Import it again or choose another image.',
      );
    }
    if (!extensions.contains(
      p.extension(path).replaceFirst('.', '').toLowerCase(),
    )) {
      throw const ArtworkFailure('Choose a JPEG, PNG, WebP, GIF or BMP image.');
    }
    if (await file.length() > maxBytes) {
      throw const ArtworkFailure('Choose an image smaller than 16 MB.');
    }
    await _validate(await file.readAsBytes());
  }

  Future<void> _validate(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const ArtworkFailure(
        'Choose a non-empty image smaller than 16 MB.',
      );
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 32000000) {
        throw const ArtworkFailure(
          'Choose an image up to 8192 pixels per side and 32 megapixels.',
        );
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width.clamp(1, 512),
      );
      if (codec.frameCount != 1) {
        throw const ArtworkFailure(
          'Choose a still image; animated artwork is not supported.',
        );
      }
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } on ArtworkFailure {
      rethrow;
    } catch (_) {
      throw const ArtworkFailure(
        'This image cannot be decoded. Choose a supported, undamaged image.',
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<String> importImage(String source, int id, bool cover) async {
    await validate(source);
    // Read and validate the exact bytes copied, even if the source changed.
    final bytes = await File(source).readAsBytes();
    await _validate(bytes);
    await directory.create(recursive: true);
    final name = p
        .basenameWithoutExtension(source)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final target = File(
      p.join(
        directory.path,
        '${id}_${cover ? 'cover' : 'banner'}_${DateTime.now().microsecondsSinceEpoch}_${name.substring(0, name.length.clamp(0, 50))}${p.extension(source).toLowerCase()}',
      ),
    );
    await target.create(exclusive: true);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  /// Explicitly requested checks against the same Steam CDN used by metadata.
  /// No historical/promotional variants are inferred from filenames.
  Future<List<String>> steamChoices(
    int id,
    bool cover,
    List<String> existing, {
    http.Client? client,
  }) async {
    if (id <= 0) return [];
    final ownClient = client == null;
    final connection = client ?? http.Client();
    final found = <String>[];
    final known = existing.toSet().toList();
    try {
      await directory.create(recursive: true);
      for (final kind in [
        cover ? 'library_600x900' : 'library_hero',
        'header',
      ]) {
        final file = File(p.join(directory.path, '${id}_steam_$kind.jpg'));
        try {
          Uint8List bytes;
          if (await file.exists()) {
            if (await file.length() > maxBytes) continue;
            bytes = await file.readAsBytes();
          } else {
            final response = await connection
                .send(
                  http.Request(
                    'GET',
                    Uri.https(
                      'cdn.akamai.steamstatic.com',
                      '/steam/apps/$id/$kind.jpg',
                    ),
                  ),
                )
                .timeout(const Duration(seconds: 10));
            if (response.statusCode != 200 ||
                !(response.headers['content-type'] ?? '').startsWith(
                  'image/',
                ) ||
                (response.contentLength ?? 0) > maxBytes) {
              await response.stream.listen(null).cancel();
              continue;
            }
            final data = BytesBuilder(copy: false);
            await for (final chunk in response.stream.timeout(
              const Duration(seconds: 10),
            )) {
              if (data.length + chunk.length > maxBytes) {
                throw const ArtworkFailure('Steam image too large.');
              }
              data.add(chunk);
            }
            bytes = data.takeBytes();
            await _validate(bytes);
            // A cached candidate is immutable; never replace a selected file.
            await file.writeAsBytes(bytes, flush: true);
          }
          await _validate(bytes);
          var duplicate = false;
          for (final path in known) {
            try {
              final other = File(path);
              if (await other.length() == bytes.length &&
                  listEquals(await other.readAsBytes(), bytes)) {
                duplicate = true;
                break;
              }
            } catch (_) {}
          }
          if (duplicate) continue;
          known.add(file.path);
          found.add(file.path);
        } catch (_) {
          /* Unavailable/invalid candidates are not offered. */
        }
      }
    } finally {
      if (ownClient) connection.close();
    }
    return found;
  }
}
