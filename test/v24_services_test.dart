import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/epic_scanner.dart';
import 'package:gamevault/services/installed_storage.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/metadata_provider.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_updates.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/services/windows_startup.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/library_query.dart';
import 'services_test.dart'
    show fixtureDirectory, manifest, TestHltb, TestMetadata;

VaultGame game(int id, {String? title}) => VaultGame(
  appId: id,
  title: title ?? 'Game $id',
  installPath: 'install',
  libraryPath: 'library',
);

Future<void> epicRecord(
  Directory manifests,
  Directory install, {
  String filename = 'game.item',
  String app = 'Sugar',
  bool incomplete = false,
  String relative = 'Binaries/Game.exe',
}) async {
  await manifests.create(recursive: true);
  final exe = File(p.join(install.path, 'Binaries', 'Game.exe'));
  await exe.parent.create(recursive: true);
  await exe.writeAsBytes([1, 2, 3]);
  await File(p.join(manifests.path, filename)).writeAsString(
    jsonEncode({
      'bIsApplication': true,
      'bIsIncompleteInstall': incomplete,
      'AppName': app,
      'CatalogNamespace': 'sandbox',
      'CatalogItemId': 'catalog',
      'DisplayName': 'Rocket Example',
      'InstallLocation': install.path,
      'LaunchExecutable': relative,
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'both history sort directions put unplayed last and break ties by title',
    () {
      final games = [
        game(1, title: 'New'),
        game(2, title: 'Old'),
        game(3, title: 'Unplayed'),
        game(4, title: 'Also old'),
      ];
      final dates = {
        1: DateTime(2026, 10, 26),
        2: DateTime(2026, 1),
        4: DateTime(2026, 1),
      };
      expect(
        queryLibrary(
          games,
          lastPlayed: (id) => dates[id],
          sort: LibrarySort.recentlyPlayed,
        ).map((g) => g.appId),
        [1, 4, 2, 3],
      );
      expect(
        queryLibrary(
          games,
          lastPlayed: (id) => dates[id],
          sort: LibrarySort.leastRecentlyPlayed,
        ).map((g) => g.appId),
        [4, 2, 1, 3],
      );
    },
  );
  test(
    'Needs Update uses live badge evidence with search and sorting; completion removes game',
    () {
      final games = [game(1), game(2), game(3)];
      for (final state in SteamUpdateState.values) {
        final evidence = SteamUpdateEvidence(state, 'Fixture');
        final list = queryLibrary(
          games,
          lastPlayed: (_) => null,
          needsUpdate: true,
          search: 'Game',
          sort: LibrarySort.recentlyPlayed,
          updates: {
            1: evidence,
            2: const SteamUpdateEvidence(
              SteamUpdateState.available,
              'Old',
              lastKnown: true,
            ),
          },
        );
        expect(list.map((g) => g.appId), evidence.badge == null ? [] : [1]);
      }
      expect(
        queryLibrary(
          games,
          lastPlayed: (_) => null,
          needsUpdate: true,
          updates: {
            1: const SteamUpdateEvidence(
              SteamUpdateState.noUpdateRecorded,
              'Complete',
            ),
          },
        ),
        isEmpty,
      );
    },
  );
  test(
    'empty manual paths discover registered Steam and linked secondary libraries',
    () async {
      final dir = await fixtureDirectory();
      try {
        final secondary = Directory(p.join(dir.path, 'secondary'));
        await manifest(dir, 10, 'Main');
        await manifest(secondary, 20, 'Secondary');
        await File(
          p.join(dir.path, 'steamapps', 'libraryfolders.vdf'),
        ).writeAsString(
          '"libraryfolders" { "1" { "path" "${secondary.path.replaceAll('\\', '\\\\')}" } }',
        );
        final scanner = SteamScanner(installationRoots: () async => [dir.path]);
        expect((await scanner.scan([])).games.map((g) => g.appId).toSet(), {
          10,
          20,
        });
        expect((await scanner.scan([secondary.path])).paths.length, 2);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Epic validates manifests, incomplete/missing/path escape and duplicate identities',
    () async {
      final dir = await fixtureDirectory();
      try {
        final records = Directory(p.join(dir.path, 'records')),
            install = Directory(p.join(dir.path, 'game'));
        await epicRecord(records, install);
        final scanner = EpicScanner(manifests: records);
        final item = (await scanner.scan()).games.single;
        expect(item.path, install.path);
        expect(
          item.identity.launchUri,
          'com.epicgames.launcher://apps/sandbox%3Acatalog%3ASugar?action=launch&silent=true',
        );
        await epicRecord(
          records,
          install,
          filename: 'escape.item',
          app: 'Escape',
          relative: '../outside.exe',
        );
        await epicRecord(
          records,
          install,
          filename: 'partial.item',
          app: 'Partial',
          incomplete: true,
        );
        await File(p.join(records.path, 'corrupt.item')).writeAsString('bad');
        final result = await scanner.scan();
        expect(result.games.length, 1);
        expect(result.warnings, isNotEmpty);
        await epicRecord(
          records,
          Directory(p.join(dir.path, 'other')),
          filename: 'duplicate.item',
        );
        expect((await scanner.scan()).games, isEmpty);
        expect(
          (await EpicScanner(
            manifests: Directory(p.join(dir.path, 'absent')),
          ).scan()).games,
          isEmpty,
        );
        await File(p.join(install.path, 'Binaries', 'Game.exe')).delete();
        expect(
          (await scanner.scan()).games.where((g) => g.path == install.path),
          isEmpty,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Epic import uses a noncolliding vault ID, persists, deduplicates and resolves relocation',
    () async {
      final dir = await fixtureDirectory();
      final records = Directory(p.join(dir.path, 'records')),
          install = Directory(p.join(dir.path, 'game'));
      await epicRecord(records, install);
      final c = VaultController(
        store: LocalStore(Directory(p.join(dir.path, 'vault'))),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
        epicScanner: EpicScanner(manifests: records),
      );
      await c.initialize();
      try {
        c.games = [game(-1)];
        await c.scan();
        final id = c.detected.single.appId;
        expect(id, -2);
        expect(c.games.length, 1);
        final manual = await File(
          p.join(dir.path, 'another.exe'),
        ).writeAsBytes([1]);
        await c.addManual('Another local game', manual.path);
        expect(c.games.last.appId, -3);
        await c.importGames({id});
        expect(c.game(id)!.isEpic, true);
        expect(c.game(-1)!.isManual, true);
        final loaded = (await c.store.load()).games.singleWhere(
          (g) => g.isEpic,
        );
        expect(loaded.epic!.key, 'sandbox:catalog:Sugar');
        await c.scan();
        await c.importGames({c.detected.single.appId});
        expect(c.games.length, 3);
        final moved = Directory(p.join(dir.path, 'moved'));
        await epicRecord(records, moved);
        await c.refreshInstallation(id, feedback: false);
        expect(c.game(id)!.installPath, moved.path);
        expect(c.game(id)!.appId, id);
        expect(c.tracker.sessions, isEmpty);
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Epic launch dispatch is distinct from Steam and metadata never queries Steam for Epic',
    () async {
      final dir = await fixtureDirectory();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsGames.channel, (call) async {
            calls.add(call);
            return null;
          });
      try {
        final g = VaultGame(
          appId: -9,
          title: 'Epic fixture',
          installPath: dir.path,
          libraryPath: dir.path,
          source: GameSource.epic,
          epic: const EpicIdentity('sandbox', 'catalog', 'Sugar'),
        );
        await WindowsGames().launch(g);
        expect(calls.single.method, 'openEpic');
        expect(calls.single.arguments, {
          'namespace': 'sandbox',
          'catalogId': 'catalog',
          'appName': 'Sugar',
        });
        await WindowsGames().launch(game(20));
        expect(calls.last.method, 'launch');
        expect(calls.last.arguments['steamId'], 20);
        var requests = 0;
        final provider = SteamMetadataProvider(
          dir,
          client: MockClient((_) async {
            requests++;
            throw StateError('No Steam request for Epic');
          }),
        );
        expect((await provider.enrich(g)).title, g.title);
        expect(requests, 0);
        provider.client.close();
        expect(
          () => const EpicIdentity('bad?', 'catalog', 'app').launchUri,
          throwsFormatException,
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowsGames.channel, null);
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'storage measures real bytes, missing paths gracefully, and scans on worker isolate',
    () async {
      final dir = await fixtureDirectory();
      try {
        final root = Directory(p.join(dir.path, 'game'));
        await root.create();
        await File(p.join(root.path, 'a')).writeAsBytes(List.filled(1200, 0));
        final nested = Directory(p.join(root.path, 'nested'));
        await nested.create();
        await File(p.join(nested.path, 'b')).writeAsBytes(List.filled(800, 0));
        final service = InstalledStorageService(
          File(p.join(dir.path, 'cache.json')),
        );
        expect((await service.inspect(root.path)).bytes, 2000);
        expect(
          (await service.inspect(p.join(dir.path, 'missing'))).bytes,
          isNull,
        );
        expect(storageSize(1500000000), '1.50 GB');
        expect(storageSize(null), 'Unavailable');
        expect(
          InstalledStorage(r'G:\Games\Example', 0, DateTime(2026)).drive,
          'G:',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'storage cache survives reload, deduplicates work, expires and refreshes on request/path change',
    () async {
      final dir = await fixtureDirectory();
      var scans = 0;
      var now = DateTime(2026, 10, 26);
      Future<InstalledStorage> measure(String root) async {
        scans++;
        await Future<void>.delayed(Duration.zero);
        return InstalledStorage(root, scans, now);
      }

      try {
        final file = File(p.join(dir.path, 'cache.json'));
        final service = InstalledStorageService(
          file,
          measure: measure,
          now: () => now,
        );
        await Future.wait([
          service.inspect(dir.path),
          service.inspect(dir.path),
        ]);
        expect(scans, 1);
        await InstalledStorageService(
          file,
          measure: measure,
          now: () => now,
        ).inspect(dir.path);
        expect(scans, 1);
        await service.inspect(dir.path, refresh: true);
        expect(scans, 2);
        now = now.add(const Duration(hours: 25));
        await service.inspect(dir.path);
        expect(scans, 3);
        await service.inspect(p.join(dir.path, 'relocated'));
        expect(scans, 4);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'startup registrations are explicit, per-user, quoted, idempotent and candidate-safe',
    () async {
      final dir = await fixtureDirectory();
      final exe = await File(
        p.join(dir.path, 'gamevault.exe'),
      ).writeAsBytes([1]);
      String? registration;
      final commands = <List<String>>[];
      Future<ProcessResult> runner(String command, List<String> args) async {
        expect(command, 'reg.exe');
        expect(args[1], WindowsStartup.key);
        commands.add(List.of(args));
        if (args.first == 'query') {
          return ProcessResult(
            1,
            registration == null ? 1 : 0,
            registration == null
                ? ''
                : '    GameVault    REG_SZ    $registration',
            '',
          );
        }
        if (args.first == 'add') {
          registration = args[args.indexOf('/d') + 1];
        } else if (args.first == 'delete') {
          registration = null;
        }
        return ProcessResult(1, 0, '', '');
      }

      try {
        final service = WindowsStartup(
          allowed: true,
          executable: exe.path,
          run: runner,
        );
        expect(await service.read(), isNull);
        await service.setEnabled(true);
        expect(registration, '"${exe.path}"');
        await service.setEnabled(true);
        expect(commands.where((c) => c.first == 'add').length, 1);
        await service.setEnabled(false);
        expect(registration, isNull);
        registration = '"C:\\Other\\other.exe"';
        await expectLater(
          service.setEnabled(false),
          throwsA(isA<FileSystemException>()),
        );
        expect(registration, contains('other.exe'));
        commands.clear();
        final candidate = WindowsStartup(
          allowed: false,
          executable: exe.path,
          run: runner,
        );
        await expectLater(
          candidate.setEnabled(true),
          throwsA(isA<FileSystemException>()),
        );
        expect(await candidate.read(), isNull);
        expect(commands, isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'startup persistence failure restores previous registry state without touching another app',
    () async {
      final dir = await fixtureDirectory();
      final exe = await File(
        p.join(dir.path, 'gamevault.exe'),
      ).writeAsBytes([1]);
      String? registration;
      final startup = WindowsStartup(
        allowed: true,
        executable: exe.path,
        run: (command, args) async {
          if (args.first == 'query') {
            return ProcessResult(
              1,
              registration == null ? 1 : 0,
              registration == null ? '' : 'GameVault REG_SZ $registration',
              '',
            );
          }
          if (args.first == 'add') registration = args[args.indexOf('/d') + 1];
          if (args.first == 'delete') registration = null;
          return ProcessResult(1, 0, '', '');
        },
      );
      final c = VaultController(
        store: LocalStore(Directory(p.join(dir.path, 'vault'))),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
        startup: startup,
      );
      await c.initialize();
      try {
        final pending = Directory('${c.store.file.path}.pending');
        await pending.create();
        await c.setStartup(true);
        expect(registration, isNull);
        expect(c.settings.startupEnabled, false);
        await pending.delete();
        await c.setStartup(true);
        expect(registration, startup.command);
        expect((await c.store.load()).settings.startupEnabled, true);
        await c.setStartup(false);
        expect(registration, isNull);
        expect(c.settings.startupEnabled, false);
      } finally {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'legacy records and settings retain identity; new preferences round trip additively',
    () {
      final legacy = game(-2).toJson()..remove('source');
      expect(VaultGame.fromJson(legacy).isManual, true);
      final old = const VaultSettings().toJson()
        ..remove('sidebarCollapsed')
        ..remove('startupEnabled');
      expect(VaultSettings.fromJson(old).startupEnabled, false);
      final settings = VaultSettings.fromJson(
        old,
      ).copy(sidebarCollapsed: true, startupEnabled: true);
      expect(VaultSettings.fromJson(settings.toJson()).sidebarCollapsed, true);
      expect(VaultSettings.fromJson(settings.toJson()).startupEnabled, true);
    },
  );
}
