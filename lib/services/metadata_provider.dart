import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/game.dart';

abstract class GameMetadataProvider {
  Future<VaultGame> enrich(VaultGame game);
}

class SteamMetadataProvider implements GameMetadataProvider {
  SteamMetadataProvider(this.cache, {http.Client? client})
    : client = client ?? http.Client();
  final Directory cache;
  final http.Client client;
  Future<String?> _image(int id, String kind, List<String> urls) async {
    await cache.create(recursive: true);
    final file = File(p.join(cache.path, '${id}_$kind.jpg'));
    if (await file.exists()) {
      // Existing cache files may be selected or retained as original artwork.
      // Never overwrite them during metadata refresh, even if damaged.
      return await file.length() > 100 ? file.path : null;
    }
    for (final url in urls) {
      try {
        final r = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200 &&
            (r.headers['content-type'] ?? '').startsWith('image/') &&
            r.bodyBytes.length > 100 &&
            r.bodyBytes.length < 15000000) {
          await file.writeAsBytes(r.bodyBytes, flush: true);
          return file.path;
        }
      } catch (e) {
        stderr.writeln('Artwork $id/$kind: $e');
      }
    }
    return null;
  }

  @override
  Future<VaultGame> enrich(VaultGame game) async {
    var updated = game;
    String? header;
    try {
      final r = await client
          .get(
            Uri.https('store.steampowered.com', '/api/appdetails', {
              'appids': game.appId.toString(),
              'l': 'english',
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        throw const FormatException('Metadata unavailable');
      }
      final data = (jsonDecode(r.body) as Map)[game.appId.toString()];
      if (data is! Map || data['success'] != true || data['data'] is! Map) {
        throw const FormatException('No Steam store metadata');
      }
      final j = data['data'] as Map;
      header = j['header_image'] as String?;
      String? names(dynamic v) =>
          v is List && v.isNotEmpty ? v.join(', ') : null;
      updated = game.copy(
        title: j['name'] as String?,
        developer: names(j['developers']),
        publisher: names(j['publishers']),
        release: j['release_date'] is Map
            ? j['release_date']['date'] as String?
            : null,
        genres: (j['genres'] as List? ?? [])
            .map((e) => e['description'].toString())
            .toList(),
        metadataMessage: 'Steam metadata cached',
      );
    } catch (e) {
      stderr.writeln('Steam metadata ${game.appId}: $e');
      updated = game.copy(
        metadataMessage:
            'Store metadata unavailable. Local Steam title and identifiers are preserved.',
      );
    }
    final base = 'https://cdn.akamai.steamstatic.com/steam/apps/${game.appId}';
    final images = await Future.wait([
      _image(game.appId, 'cover', ['$base/library_600x900.jpg', ?header]),
      _image(game.appId, 'hero', [
        '$base/library_hero.jpg',
        ?header,
        '$base/header.jpg',
      ]),
    ]);
    return updated.copy(coverPath: images[0], heroPath: images[1]);
  }
}
