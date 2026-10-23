import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_installation.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/details_page.dart';
import 'services_test.dart' show TestMetadata, TestHltb;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gamevault_installation_');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  VaultGame game(String root) => VaultGame(
    appId: 1,
    title: 'Example',
    installPath: p.join(root, 'steamapps', 'common', 'Example'),
    libraryPath: root,
    favorite: true,
    hltb: const HltbEntry(id: 9, title: 'Example', main: 10),
  );
  Future<void> installed(
    String root, {
    String dir = 'Example',
    String extra = '',
  }) async {
    await Directory(
      p.join(root, 'steamapps', 'common', dir),
    ).create(recursive: true);
    await File(p.join(root, 'steamapps', 'appmanifest_1.acf')).writeAsString(
      '"AppState" { "appid" "1" "installdir" "$dir" "buildid" "123" "stateflags" "4" $extra }',
    );
  }

  test(
    'configured C/D/G library relocations are repaired without losing data',
    () async {
      for (final from in ['C', 'D', 'G']) {
        for (final to in ['C', 'D', 'G'].where((x) => x != from)) {
          final root = await Directory(p.join(temp.path, '$from-$to')).create();
          final old = p.join(root.path, from), newer = p.join(root.path, to);
          await Directory(p.join(old, 'steamapps')).create(recursive: true);
          await installed(newer);
          await File(
            p.join(old, 'steamapps', 'libraryfolders.vdf'),
          ).writeAsString(
            '"libraryfolders" { "0" { "path" "${newer.replaceAll('\\', '\\\\')}" } }',
          );
          final override = await File(
            p.join(root.path, 'custom.exe'),
          ).writeAsString('fixture');
          final scanner = SteamScanner(installationRoots: () async => [old]);
          final c = VaultController(
            store: LocalStore(Directory(p.join(root.path, 'test-vault'))),
            scanner: scanner,
            metadata: TestMetadata(),
            hltb: TestHltb(),
          );
          await c.initialize();
          c.games = [game(old).copy(executablePath: override.path)];
          final evidence = await SteamInstallation(
            scanner,
          ).inspect(c.games.single, []);
          expect(evidence.status, InstallationStatus.needsRefresh);
          await c.refreshInstallation(1);
          expect(
            c.games.single.installPath,
            p.join(newer, 'steamapps', 'common', 'Example'),
          );
          expect(c.games.single.executablePath, override.path);
          expect(c.games.single.favorite, true);
          expect(c.games.single.hltb!.main, 10);
          expect(c.tracker.sessions, isEmpty);
          final oldExe = p.join(game(old).installPath, 'Binaries', 'game.exe');
          final newExe = p.join(
            game(newer).installPath,
            'Binaries',
            'game.exe',
          );
          await Directory(p.dirname(newExe)).create(recursive: true);
          await File(newExe).writeAsString('fixture');
          await c.update(1, (g) => g.copy(executablePath: oldExe));
          await c.refreshInstallation(1);
          // A stale override from outside the current root remains explicit,
          // rather than being guessed or discarded on a later refresh.
          expect(c.games.single.executablePath, oldExe);
          await c.update(1, (g) => g.copy(installPath: game(old).installPath));
          await c.refreshInstallation(1);
          expect(c.games.single.executablePath, newExe);
          await c.shutdown();
          final saved = await c.store.load();
          expect(saved.games.single.installPath, game(newer).installPath);
          expect(saved.games.single.executablePath, newExe);
          expect(saved.games.single.hltb!.main, 10);
          c.dispose();
        }
      }
    },
  );
  test(
    'missing manifest does not mean uninstalled, traversal and duplicate manifests are rejected',
    () async {
      final a = p.join(temp.path, 'A'), b = p.join(temp.path, 'B');
      await Directory(game(a).installPath).create(recursive: true);
      final scanner = SteamScanner(installationRoots: () async => [a, b]);
      final service = SteamInstallation(scanner);
      expect(
        (await service.inspect(game(a), [])).status,
        InstallationStatus.unknown,
      );
      await installed(a, dir: '..');
      expect((await service.inspect(game(a), [])).installPath, isNull);
      await installed(a);
      await installed(b);
      expect((await service.inspect(game(a), [])).installPath, isNull);
    },
  );
  test(
    'unavailable library and corrupted metadata cannot fabricate installation or update',
    () async {
      final root = p.join(temp.path, 'Unavailable');
      final service = SteamInstallation(
        SteamScanner(installationRoots: () async => [root]),
      );
      expect(
        (await service.inspect(game(root), [])).status,
        InstallationStatus.unknown,
      );
      await Directory(p.join(root, 'steamapps')).create(recursive: true);
      await File(
        p.join(root, 'steamapps', 'appmanifest_1.acf'),
      ).writeAsString('"AppState" {');
      final e = await service.inspect(game(root), []);
      expect(e.status, InstallationStatus.unknown);
      expect(e.buildId, isNull);
    },
  );
  test(
    'Steam launch reaches native Steam URI dispatcher despite stale installation and tracking paths',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsGames.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowsGames.channel, null),
      );
      await WindowsGames().launch(
        game(p.join(temp.path, 'missing')).copy(executablePath: 'missing.exe'),
      );
      expect(calls.single.method, 'launch');
      expect(calls.single.arguments, {'steamId': 1, 'executable': ''});
      await expectLater(
        WindowsGames().launch(
          VaultGame(
            appId: -1,
            title: 'Manual',
            installPath: temp.path,
            libraryPath: temp.path,
            executablePath: 'missing.exe',
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  test(
    'file location verifies moved Steam root even if stale folder survives, without saving',
    () async {
      final old = p.join(temp.path, 'OldDrive');
      final actual = p.join(temp.path, 'OtherDrive');
      await Directory(game(old).installPath).create(recursive: true);
      await installed(actual);
      final scanner = SteamScanner(
        installationRoots: () async => [old, actual],
      );
      final c = VaultController(
        store: LocalStore(Directory(p.join(temp.path, 'vault'))),
        scanner: scanner,
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      await c.initialize();
      c.games = [game(old)];
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsGames.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowsGames.channel, null),
      );
      await c.openGameLocation(1);
      expect(calls.single.method, 'openLocation');
      expect(calls.single.arguments, {
        'path': game(actual).installPath,
        'select': false,
      });
      expect(c.games.single.installPath, game(old).installPath);
      expect(await c.store.file.exists(), false);
      // A duplicate is inconclusive; never open either directory by guessing.
      calls.clear();
      await installed(old);
      await c.openGameLocation(1);
      expect(calls, isEmpty);
      expect(c.error, contains('could not be opened'));
      await File(p.join(old, 'steamapps', 'appmanifest_1.acf')).delete();
      await File(p.join(actual, 'steamapps', 'appmanifest_1.acf')).delete();
      await c.openGameLocation(1);
      expect(calls, isEmpty);
      await c.shutdown();
      c.dispose();
    },
  );
  test(
    'local directories and EXE selection use existing native opening and handle missing paths',
    () async {
      final exe = await File(
        p.join(temp.path, 'local.exe'),
      ).writeAsString('fixture');
      final c = VaultController(
        store: LocalStore(Directory(p.join(temp.path, 'vault'))),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      await c.initialize();
      c.games = [
        VaultGame(
          appId: -1,
          title: 'Local',
          installPath: temp.path,
          libraryPath: '',
          executablePath: exe.path,
        ),
      ];
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsGames.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowsGames.channel, null),
      );
      await c.openGameLocation(-1);
      expect(calls.last.arguments, {'path': temp.path, 'select': false});
      await c.openGameLocation(-1, executable: true);
      expect(calls.last.arguments, {'path': exe.path, 'select': true});
      c.games = [
        c.games.single.copy(installPath: p.join(temp.path, 'missing')),
      ];
      await c.openGameLocation(-1);
      expect(calls.last.arguments, {'path': temp.path, 'select': false});
      await exe.delete();
      calls.clear();
      await c.openGameLocation(-1);
      expect(calls, isEmpty);
      expect(c.error, contains('could not be opened'));
      await c.shutdown();
      c.dispose();
    },
  );
  test(
    'narrow Expanded uses widescreen cap while desktop sizes remain unchanged',
    () {
      for (final size in ProfileSize.values) {
        expect(profileArtworkHeight(size, 360), lessThanOrEqualTo(176));
      }
      expect(profileArtworkHeight(ProfileSize.expanded, 1280), 420);
      expect(profileArtworkHeight(ProfileSize.comfortable, 1280), 260);
    },
  );
}
