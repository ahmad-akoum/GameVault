import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final client = http.Client();
  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Referer': 'https://howlongtobeat.com/',
    'Origin': 'https://howlongtobeat.com',
  };
  for (final path in [
    '/api/find/init',
    '/api/s/init',
    '/api/search/site/init',
    '/',
  ]) {
    final r = await client.get(
      Uri.parse('https://howlongtobeat.com$path'),
      headers: headers,
    );
    stdout.writeln('$path: ${r.statusCode}');
    if (path == '/') {
      final urls = RegExp(
        r'''src=["']([^"']*/_next/static/chunks/[^"']+)["']''',
      ).allMatches(r.body).map((m) => m.group(1)!).toList();
      for (final src in urls) {
        final script = await client.get(
          Uri.parse('https://howlongtobeat.com').resolve(src),
          headers: headers,
        );
        final matches = RegExp(
          r'''/api/[A-Za-z0-9_/]+''',
        ).allMatches(script.body).map((m) => m.group(0)).toSet();
        if (matches.isNotEmpty) {
          stdout.writeln('$src: $matches');
        }
      }
    }
  }
  client.close();
}
