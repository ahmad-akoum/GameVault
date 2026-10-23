import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gamevault/services/hltb_provider.dart';
import 'package:gamevault/models/game.dart';

void main() {
  test(
    'restored init/search protocol retrieves all three durations and Steam reference',
    () async {
      final calls = <http.Request>[];
      final provider = WebsiteHltbProvider(
        client: MockClient((r) async {
          calls.add(r);
          if (r.method == 'GET') {
            return http.Response(jsonEncode({'token': 'fixture-token'}), 200);
          }
          expect(r.headers['x-auth-token'], 'fixture-token');
          expect(jsonDecode(r.body)['searchTerms'], ['Elden', 'Ring']);
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'game_id': 42,
                  'game_name': 'Elden Ring',
                  'comp_main': 36000,
                  'comp_plus': 72000,
                  'comp_100': 108000,
                  'profile_steam': '1245620',
                },
              ],
            }),
            200,
          );
        }),
      );
      final results = await provider.search('Elden Ring');
      expect(calls.map((r) => r.method), ['GET', 'POST']);
      expect(results.single.main, 10);
      expect(results.single.extras, 20);
      expect(results.single.complete, 30);
      expect(results.single.steamId, 1245620);
    },
  );
  for (final status in [401, 403, 429, 500]) {
    test(
      'HTTP $status stops without script inspection, retry or fabricated result',
      () async {
        var calls = 0;
        final provider = WebsiteHltbProvider(
          client: MockClient((r) async {
            calls++;
            return http.Response('denied', status);
          }),
        );
        await expectLater(
          provider.search('Game'),
          throwsA(
            isA<HltbFailure>().having(
              (e) => e.state,
              'state',
              HltbState.unavailable,
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }
  test(
    'network and malformed data produce failures instead of successful empty results',
    () async {
      final offline = WebsiteHltbProvider(
        client: MockClient((r) async {
          throw const SocketException('offline');
        }),
      );
      await expectLater(
        offline.search('Game'),
        throwsA(
          isA<HltbFailure>().having(
            (e) => e.state,
            'state',
            HltbState.networkError,
          ),
        ),
      );
      final bad = WebsiteHltbProvider(
        client: MockClient((r) async => http.Response('not json', 200)),
      );
      await expectLater(bad.search('Game'), throwsA(isA<HltbFailure>()));
    },
  );
}
