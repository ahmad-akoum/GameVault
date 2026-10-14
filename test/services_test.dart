import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/hltb_provider.dart';
import 'package:gamevault/services/metadata_provider.dart';
import 'package:gamevault/state/vault_controller.dart';

class TestMetadata implements GameMetadataProvider {
  Completer<void>? gate;
  @override
  Future<VaultGame> enrich(VaultGame game) async {
    if (gate != null) {
      await gate!.future;
    }
    return game.copy(developer: 'Fixture developer');
  }
}

class TestHltb implements HltbProvider {
  List<HltbEntry> results = [];
  HltbFailure? failure;
  @override
  Future<List<HltbEntry>> search(String title) async {
    if (failure != null) {
      throw failure!;
    }
    return results;
  }
}

Future<Directory> fixtureDirectory() async {
  final dir = Directory(p.join(Directory.current.path, 'build', 'test_data'));
  await dir.create(recursive: true);
  return dir.createTemp('case_');
}

Future<void> manifest(
  Directory library,
  int id,
  String title, {
  String flags = '4',
  bool installed = true,
}) async {
  final apps = Directory(p.join(library.path, 'steamapps'));
  await apps.create(recursive: true);
  if (installed) {
    await Directory(p.join(apps.path, 'common', title)).create(recursive: true);
  }
  await File(p.join(apps.path, 'appmanifest_$id.acf')).writeAsString(
    '"AppState" { "appid" "$id" "name" "$title" "installdir" "$title" "StateFlags" "$flags" }',
  );
}

void main() {
  group('Valve KeyValues', () {
    test('nested values, escaped Windows paths, comments and case', () {
      final v = ValveKeyValues.parse(r'''// header
      "LibraryFolders" { "0" { "path" "D:\\SteamLibrary" } "note" "quote\"here" }
      ''');
      expect(v['libraryfolders']['0']['path'], r'D:\SteamLibrary');
      expect(v['libraryfolders']['note'], 'quote"here');
    });
    for (final bad in [
      '"a" { "b" "c"',
      '"a"',
      '}',
      '"a" "unterminated',
      '"a" }',
    ]) {
      test(
        'reject malformed $bad',
        () => expect(() => ValveKeyValues.parse(bad), throwsFormatException),
      );
    }
  });
  group('Steam scanner', () {
    late Directory dir;
    setUp(() async => dir = await fixtureDirectory());
    tearDown(() async => dir.delete(recursive: true));
    test('invalid path produces useful failure', () async {
      await expectLater(
        SteamScanner(
          installationRoots: () async => [],
        ).scan([p.join(dir.path, 'missing')]),
        throwsA(isA<ScanFailure>()),
      );
    });
    test(
      'manifest identity, installed flags, missing files, duplicates and malformed files',
      () async {
        final a = Directory(p.join(dir.path, 'a'));
        final b = Directory(p.join(dir.path, 'b'));
        await manifest(a, 10, 'Counter Strike');
        await manifest(b, 10, 'Counter Strike');
        await manifest(a, 20, 'Incomplete', flags: '1');
        await manifest(a, 30, 'Missing', installed: false);
        await File(
          p.join(a.path, 'steamapps', 'appmanifest_40.acf'),
        ).writeAsString('broken {');
        final r = await SteamScanner(
          installationRoots: () async => [],
        ).scan([a.path, b.path]);
        expect(r.games.length, 1);
        expect(r.games.single.appId, 10);
        expect(
          r.games.single.installPath,
          p.join(a.path, 'steamapps', 'common', 'Counter Strike'),
        );
        expect(r.warnings.length, 4);
      },
    );
    test(
      'libraryfolders discovers linked paths and steamapps root is accepted',
      () async {
        final a = Directory(p.join(dir.path, 'a'));
        final b = Directory(p.join(dir.path, 'b'));
        await manifest(a, 10, 'One');
        await manifest(b, 20, 'Two');
        final escaped = b.path.replaceAll('\\', '\\\\');
        await File(
          p.join(a.path, 'steamapps', 'libraryfolders.vdf'),
        ).writeAsString('"libraryfolders" { "1" { "path" "$escaped" } }');
        final r = await SteamScanner(
          installationRoots: () async => [],
        ).scan([p.join(a.path, 'steamapps')]);
        expect(r.games.map((g) => g.appId), [10, 20]);
      },
    );
    test('empty valid library succeeds without importing anything', () async {
      await Directory(p.join(dir.path, 'steamapps')).create();
      expect(
        (await SteamScanner(
          installationRoots: () async => [],
        ).scan([dir.path])).games,
        isEmpty,
      );
    });
  });
  group('Persistence', () {
    late Directory dir;
    late LocalStore store;
    setUp(() async {
      dir = await fixtureDirectory();
      store = LocalStore(dir);
    });
    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    test(
      'games, HLTB, status, favorites, appearance and paths survive reopening',
      () async {
        final game = VaultGame(
          appId: 10,
          title: 'Game',
          installPath: 'C:\\Game',
          libraryPath: 'C:\\Steam',
          favorite: true,
          status: GameStatus.completionist,
          hltbState: HltbState.matched,
          hltb: const HltbEntry(
            id: 3,
            title: 'Game',
            main: 5,
            extras: 8,
            complete: 10,
          ),
        );
        const settings = VaultSettings(
          theme: AppearanceMode.light,
          accent: 0xffe87d87,
          paths: ['C:\\Steam'],
        );
        await store.save([game], settings);
        final loaded = await LocalStore(dir).load();
        expect(loaded.games.single.toJson(), game.toJson());
        expect(loaded.settings.toJson(), settings.toJson());
      },
    );
    test('corrupt primary recovers from previous-good backup', () async {
      await store.save([], const VaultSettings(accent: 1));
      await store.save([], const VaultSettings(accent: 2));
      await store.file.writeAsString('{ damaged');
      final loaded = await store.load();
      expect(loaded.recovered, isTrue);
      expect(loaded.settings.accent, 1);
      await store.save([], loaded.settings);
      expect((await store.load()).settings.accent, 1);
    });
    test('unreadable documents are preserved and block startup', () async {
      await store.file.writeAsString('bad');
      await expectLater(store.load(), throwsA(isA<StorageFailure>()));
      expect(await store.file.readAsString(), 'bad');
    });
    test('serialized concurrent saves leave a valid latest snapshot', () async {
      await Future.wait(
        List.generate(10, (i) => store.save([], VaultSettings(accent: i))),
      );
      expect((await store.load()).settings.accent, 9);
    });
    test('interrupted loading state resumes as pending', () async {
      final g = VaultGame(
        appId: 1,
        title: 'a',
        installPath: 'a',
        libraryPath: 'a',
        hltbState: HltbState.loading,
      );
      await store.save([g], const VaultSettings());
      expect((await store.load()).games.single.hltbState, HltbState.pending);
    });
    test(
      'artwork paths are stored relative to the portable data folder',
      () async {
        await store.artwork.create();
        final image = File(p.join(store.artwork.path, 'one.jpg'));
        await image.writeAsString('fixture');
        final game = VaultGame(
          appId: 1,
          title: 'a',
          installPath: 'a',
          libraryPath: 'a',
          coverPath: image.path,
        );
        await store.save([game], const VaultSettings());
        final data = jsonDecode(await store.file.readAsString());
        expect(p.isAbsolute(data['games'][0]['coverPath'] as String), false);
        expect((await store.load()).games.single.coverPath, image.path);
      },
    );
    test(
      'schema-damaged primary never replaces the recovered backup',
      () async {
        await store.save([], const VaultSettings(accent: 1));
        await store.save([], const VaultSettings(accent: 2));
        await store.file.writeAsString(
          '{"version":1,"games":"invalid","settings":{}}',
        );
        final recovered = await store.load();
        await store.save(recovered.games, recovered.settings);
        expect(
          jsonDecode(await store.backup.readAsString())['settings']['accent'],
          1,
        );
      },
    );
  });
  group('HLTB protocol and matching', () {
    test(
      'real response schema converts seconds to hours and zero stays unavailable',
      () async {
        final provider = WebsiteHltbProvider(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/init')) {
              return http.Response('{"token":"test"}', 200);
            }
            expect(request.headers['x-auth-token'], 'test');
            expect(jsonDecode(request.body)['searchTerms'], ['Portal', '2']);
            return http.Response(
              '{"data":[{"game_id":1,"game_name":"Portal 2","comp_main":36000,"comp_plus":54000,"comp_100":0}]}',
              200,
            );
          }),
        );
        final entry = (await provider.search('Portal 2')).single;
        expect(entry.main, 10);
        expect(entry.extras, 15);
        expect(entry.complete, 0);
      },
    );
    test('network failure is explicit', () async {
      final provider = WebsiteHltbProvider(
        client: MockClient((r) async => throw const SocketException('offline')),
      );
      await expectLater(
        provider.search('Game'),
        throwsA(
          isA<HltbFailure>().having(
            (e) => e.state,
            'state',
            HltbState.networkError,
          ),
        ),
      );
    });
    test('rate limiting uses cooldown', () async {
      var calls = 0;
      final provider = WebsiteHltbProvider(
        client: MockClient((r) async {
          calls++;
          return http.Response('limit', 429);
        }),
      );
      await expectLater(provider.search('a'), throwsA(isA<HltbFailure>()));
      await expectLater(provider.search('b'), throwsA(isA<HltbFailure>()));
      expect(calls, 1);
    });
    test(
      'invalid search schema is unavailable, never a successful zero result',
      () async {
        final provider = WebsiteHltbProvider(
          client: MockClient(
            (r) async => http.Response(
              r.url.path.endsWith('/init') ? '{"token":"test"}' : '{}',
              200,
            ),
          ),
        );
        await expectLater(
          provider.search('a'),
          throwsA(
            isA<HltbFailure>().having(
              (e) => e.state,
              'state',
              HltbState.unavailable,
            ),
          ),
        );
      },
    );
    test('unique normalized match or AppID; ambiguity requires choice', () {
      const one = HltbEntry(id: 1, title: 'ELDEN RING™');
      const two = HltbEntry(id: 2, title: 'Elden Ring');
      expect(HltbMatcher.confidentMatch('Elden Ring', 123, [one]), one);
      expect(HltbMatcher.confidentMatch('Elden Ring', 123, [one, two]), isNull);
      expect(
        HltbMatcher.confidentMatch('Different title', 123, [
          const HltbEntry(id: 3, title: 'Other', steamId: 123),
        ])?.id,
        3,
      );
      expect(
        HltbMatcher.confidentMatch('Game', 1, [
          const HltbEntry(id: 1, title: 'Game 2'),
        ]),
        isNull,
      );
    });
  });
  group('Library controller', () {
    late Directory dir;
    late VaultController c;
    late TestHltb h;
    late TestMetadata m;
    setUp(() async {
      dir = await fixtureDirectory();
      h = TestHltb();
      m = TestMetadata();
      c = VaultController(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: m,
        hltb: h,
      );
      await c.initialize();
      c.detected = const [
        SteamGame(
          appId: 1,
          name: 'One',
          installPath: 'installation-one',
          libraryPath: 'steam',
        ),
        SteamGame(
          appId: 2,
          name: 'Two',
          installPath: 'installation-two',
          libraryPath: 'steam',
        ),
      ];
    });
    tearDown(() async {
      await c.shutdown();
      c.dispose();
      await dir.delete(recursive: true);
    });
    test(
      'only selected games import; repeated imports are idempotent',
      () async {
        await c.importGames({1});
        await c.importGames({1});
        expect(c.games.length, 1);
        expect(c.games.single.appId, 1);
        expect(c.games.single.hltbState, HltbState.noMatch);
      },
    );
    test(
      'edits made during enrichment survive; removal never modifies installation',
      () async {
        m.gate = Completer();
        final importing = c.importGames({1});
        while (c.game(1) == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await c.update(
          1,
          (g) => g.copy(favorite: true, status: GameStatus.playing),
        );
        m.gate!.complete();
        await importing;
        expect(c.game(1)!.favorite, true);
        expect(c.game(1)!.status, GameStatus.playing);
        await c.remove(1);
        expect(c.games, isEmpty);
        expect((await c.store.load()).games, isEmpty);
      },
    );
    test(
      'ambiguous selection and failed refresh preserve previously retrieved times',
      () async {
        h.results = const [
          HltbEntry(id: 1, title: 'First', main: 10),
          HltbEntry(id: 2, title: 'Second', main: 20),
        ];
        await c.importGames({1});
        expect(c.game(1)!.hltbState, HltbState.ambiguous);
        await c.selectMatch(1, h.results.last);
        expect(c.game(1)!.hltb!.main, 20);
        h.failure = const HltbFailure('offline', HltbState.networkError);
        await c.lookup(1);
        expect(c.game(1)!.hltbState, HltbState.networkError);
        expect(c.game(1)!.hltb!.main, 20);
      },
    );
    test(
      'write failure rolls back visible edits and exposes user error',
      () async {
        await c.importGames({1});
        // Turn staging destination into a directory to simulate a failed write.
        await Directory('${c.store.file.path}.pending').create();
        await c.update(1, (g) => g.copy(favorite: true));
        expect(c.game(1)!.favorite, false);
        expect(c.error, isNotNull);
      },
    );
  });
}
