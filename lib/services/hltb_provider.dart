import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/game.dart';

abstract class HltbProvider {
  Future<List<HltbEntry>> search(String title);
}

class HltbFailure implements Exception {
  const HltbFailure(this.message, this.state);
  final String message;
  final HltbState state;
}

/// Independent adapter to HLTB's public website search. No unofficial proxy,
/// account, fabricated times, or dependencies on this protocol outside here.
class WebsiteHltbProvider implements HltbProvider {
  WebsiteHltbProvider({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  String _endpoint = '/api/search/site';
  DateTime? _lastRequest, _blockedUntil;
  static const _base = 'https://howlongtobeat.com';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Referer': 'https://howlongtobeat.com/',
    'Origin': 'https://howlongtobeat.com',
    'Accept': 'application/json',
  };
  void _check(http.Response response) {
    if (response.statusCode == 429) {
      _blockedUntil = DateTime.now().add(const Duration(minutes: 2));
      throw const HltbFailure(
        'HowLongToBeat is limiting requests. Try again in a few minutes.',
        HltbState.unavailable,
      );
    }
    if (response.statusCode != 200) {
      throw HltbFailure(
        'HowLongToBeat is currently unavailable (HTTP ${response.statusCode}). Your library is still available.',
        HltbState.unavailable,
      );
    }
  }

  Future<Map<String, dynamic>> _initialize() async {
    final response = await client
        .get(
          Uri.parse(
            '$_base$_endpoint/init?t=${DateTime.now().millisecondsSinceEpoch}',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    _check(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _discoverEndpoint() async {
    final homepage = await client
        .get(Uri.parse('$_base/'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _check(homepage);
    final scripts = RegExp(
      r'''src=["']([^"']*/_next/static/chunks/[^"']+)["']''',
    ).allMatches(homepage.body).map((m) => m.group(1)!).toList();
    // Search page chunks first. Limit requests when the website changes.
    scripts.sort(
      (a, b) => (b.contains('pages/') ? 1 : 0).compareTo(
        a.contains('pages/') ? 1 : 0,
      ),
    );
    for (final src in scripts.take(24)) {
      final uri = Uri.parse('$_base/').resolve(src);
      if (uri.host != 'howlongtobeat.com') {
        continue;
      }
      final script = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final match = RegExp(
        r'''fetch\s*\(\s*["'](/api/[a-zA-Z0-9_/]+)[^"']*["']\s*,\s*\{[^}]*method:\s*["']POST["']''',
      ).firstMatch(script.body);
      if (match != null) {
        _endpoint = match.group(1)!.replaceAll(RegExp(r'/$'), '');
        return;
      }
    }
    throw const HltbFailure(
      'HowLongToBeat changed its search interface. Cached information remains available.',
      HltbState.unavailable,
    );
  }

  @override
  Future<List<HltbEntry>> search(String title) async {
    if (title.trim().isEmpty) {
      return [];
    }
    if (_blockedUntil != null && DateTime.now().isBefore(_blockedUntil!)) {
      throw const HltbFailure(
        'HowLongToBeat is limiting requests. Try again in a few minutes.',
        HltbState.unavailable,
      );
    }
    try {
      final since = _lastRequest == null
          ? 1000
          : DateTime.now().difference(_lastRequest!).inMilliseconds;
      if (since < 800) {
        await Future<void>.delayed(Duration(milliseconds: 800 - since));
      }
      _lastRequest = DateTime.now();
      Map<String, dynamic> auth;
      try {
        auth = await _initialize();
      } on HltbFailure catch (e) {
        if (_blockedUntil != null) {
          rethrow;
        }
        if (e.state != HltbState.unavailable) {
          rethrow;
        }
        await _discoverEndpoint();
        auth = await _initialize();
      }
      final token = auth['token'];
      final key = auth.entries
          .where((e) => e.key.toLowerCase().contains('key'))
          .firstOrNull
          ?.value;
      final value = auth.entries
          .where((e) => e.key.toLowerCase().contains('val'))
          .firstOrNull
          ?.value;
      if (token is! String) {
        throw const HltbFailure(
          'HowLongToBeat returned an unsupported search response.',
          HltbState.unavailable,
        );
      }
      final payload = {
        'searchType': 'games',
        'searchTerms': title.trim().split(RegExp(r'\s+')),
        'searchPage': 1,
        'size': 20,
        'useCache': true,
        if (key is String && value != null) key: value,
        'searchOptions': {
          'games': {
            'userId': 0,
            'platform': '',
            'sortCategory': 'popular',
            'rangeCategory': 'main',
            'rangeTime': {'min': 0, 'max': 0},
            'gameplay': {
              'perspective': '',
              'flow': '',
              'genre': '',
              'difficulty': '',
            },
            'rangeYear': {'min': '', 'max': ''},
            'modifier': '',
          },
          'users': {'sortCategory': 'postcount'},
          'lists': {'sortCategory': 'follows'},
          'filter': '',
          'sort': 0,
          'randomizer': 0,
        },
      };
      final response = await client
          .post(
            Uri.parse('$_base$_endpoint'),
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
              'x-auth-token': token,
              if (key is String && value != null) 'x-hp-key': key,
              if (value != null) 'x-hp-val': value.toString(),
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      _check(response);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['data'] is! List) {
        throw const FormatException('Missing results');
      }
      return (json['data'] as List).map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        double hours(String k) =>
            (num.tryParse(row[k]?.toString() ?? '') ?? 0) / 3600;
        final id = int.tryParse(row['game_id']?.toString() ?? '');
        if (id == null || row['game_name'] is! String) {
          throw const FormatException('Invalid result');
        }
        return HltbEntry(
          id: id,
          title: row['game_name'] as String,
          main: hours('comp_main'),
          extras: hours('comp_plus'),
          complete: hours('comp_100'),
          year: int.tryParse(row['release_world']?.toString() ?? ''),
          steamId: int.tryParse(row['profile_steam']?.toString() ?? ''),
        );
      }).toList();
    } on HltbFailure {
      rethrow;
    } on TimeoutException {
      throw const HltbFailure(
        'The HowLongToBeat request timed out. Try again when your connection is stable.',
        HltbState.networkError,
      );
    } on SocketException {
      throw const HltbFailure(
        'Could not connect to HowLongToBeat. Check your internet connection.',
        HltbState.networkError,
      );
    } on http.ClientException {
      throw const HltbFailure(
        'Could not connect to HowLongToBeat. Check your internet connection.',
        HltbState.networkError,
      );
    } catch (e) {
      stderr.writeln('HLTB parsing failed: $e');
      throw const HltbFailure(
        'HowLongToBeat returned an unsupported response. Try again later.',
        HltbState.unavailable,
      );
    }
  }
}

class HltbMatcher {
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[™®©]'), '')
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  static HltbEntry? confidentMatch(
    String title,
    int appId,
    List<HltbEntry> entries,
  ) {
    final byId = entries.where((e) => e.steamId == appId).toList();
    if (byId.length == 1) {
      return byId.single;
    }
    final exact = entries
        .where((e) => normalize(e.title) == normalize(title))
        .toList();
    return exact.length == 1 ? exact.single : null;
  }

  static List<HltbEntry> rank(String title, List<HltbEntry> entries) {
    final result = [...entries];
    final n = normalize(title);
    result.sort((a, b) {
      int score(HltbEntry e) => normalize(e.title) == n
          ? 2
          : normalize(e.title).contains(n)
          ? 1
          : 0;
      return score(b).compareTo(score(a));
    });
    return result;
  }
}
