import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_installation.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/installed_storage.dart';
import 'package:gamevault/services/session_tracker.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/details_page.dart';
import 'services_test.dart' show TestMetadata, TestHltb;

class _FixturePlatform implements GamePlatform {
  bool running = false;
  final launches = <int>[];
  @override
  Future<void> launch(VaultGame game) async => launches.add(game.appId);
  @override
  Future<WindowsSample> sample(List<VaultGame> games) async => WindowsSample([
    if (running)
      for (final game in games)
        GameObservation(game.appId, game.title, {'running'}, true),
  ], 0);
}

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
    'Steam launch and uninstall require unambiguous manifest evidence',
    () async {
      final a = p.join(temp.path, 'A');
      final b = p.join(temp.path, 'B');
      await installed(a);
      final platform = _FixturePlatform();
      final c = VaultController(
        store: LocalStore(temp),
        scanner: SteamScanner(installationRoots: () async => [a, b]),
        metadata: TestMetadata(),
        hltb: TestHltb(),
        platform: platform,
      );
      addTearDown(c.dispose);
      final profile = game(a);
      c.games = [profile];
      c.settings = c.settings.copy(trackingEnabled: false);
      await c.checkInstallation(1);
      expect(c.installations[1]?.status, InstallationStatus.installed);
      final manifest = File(p.join(a, 'steamapps', 'appmanifest_1.acf'));
      final valid = await manifest.readAsString();
      final other = File(p.join(b, 'steamapps', 'appmanifest_1.acf'));
      await other.parent.create(recursive: true);
      await other.writeAsString('"AppState" {');
      await c.launch(
        1,
      ); // Stale positive UI evidence cannot authorize dispatch.
      expect(c.installations[1]?.status, InstallationStatus.unknown);
      expect(await c.requestSteamInstallation(1, uninstall: true), isFalse);
      expect(platform.launches, isEmpty);
      await other.delete();
      await manifest.writeAsString(
        valid.replaceFirst('"stateflags" "4"', '"stateflags" "4194308"'),
      );
      await c.launch(1);
      expect(c.installations[1]?.status, InstallationStatus.unknown);
      expect(await c.requestSteamInstallation(1, uninstall: true), isFalse);
      expect(platform.launches, isEmpty);
      await manifest.writeAsString(valid);
      await c.launch(1);
      expect(platform.launches, [1]);
      await manifest.delete();
      await c.checkInstallation(1);
      expect(c.installations[1]?.status, InstallationStatus.missing);
      await c.shutdown();
    },
  );

  test(
    'Steam dispatch is verified and profile survives removal and reinstall',
    () async {
      final root = p.join(temp.path, 'Steam');
      await installed(root);
      final profile = game(root);
      final platform = _FixturePlatform();
      final store = LocalStore(Directory(p.join(temp.path, 'vault')));
      final c = VaultController(
        store: store,
        scanner: SteamScanner(installationRoots: () async => [root]),
        metadata: TestMetadata(),
        hltb: TestHltb(),
        platform: platform,
        storageService: InstalledStorageService(
          File(p.join(temp.path, 'sizes.json')),
        ),
      );
      addTearDown(c.dispose);
      c.games = [profile];
      final time = DateTime(2026, 1, 1);
      c.tracker.sample(
        now: time,
        monotonicSeconds: 0,
        games: [
          GameObservation(1, 'Example', {'fixture'}, true),
        ],
        idleSeconds: 0,
      );
      c.tracker.closeAll('Fixture');
      final history = c.tracker.toJson();
      await store.save([profile], c.settings, sessions: history);
      final calls = <MethodCall>[];
      var fail = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(WindowsGames.channel, (call) async {
        calls.add(call);
        if (fail) throw PlatformException(code: 'steam_unavailable');
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(WindowsGames.channel, null),
      );
      expect(await c.requestSteamInstallation(0, uninstall: true), isFalse);
      for (final unsupported in [
        for (final source in [GameSource.local, GameSource.epic])
          VaultGame(
            appId: 1,
            title: 'Unsupported',
            installPath: root,
            libraryPath: root,
            source: source,
          ),
        VaultGame(
          appId: 0x100000000,
          title: 'Invalid',
          installPath: root,
          libraryPath: root,
        ),
      ]) {
        c.games = [unsupported];
        expect(
          await c.requestSteamInstallation(unsupported.appId, uninstall: true),
          isFalse,
        );
      }
      c.games = [profile];
      platform.running = true;
      expect(await c.requestSteamInstallation(1, uninstall: true), isFalse);
      expect(calls, isEmpty);
      platform.running = false;
      expect(await c.requestSteamInstallation(1, uninstall: true), isFalse);
      expect(c.installations[1]?.status, InstallationStatus.installed);
      fail = false;
      expect(await c.requestSteamInstallation(1, uninstall: true), isTrue);
      expect(calls.last.method, 'uninstallSteam');
      expect(calls.last.arguments, {'steamId': 1});
      // A Steam cancellation or no-op leaves the same positive evidence.
      await c.checkInstallation(1, refreshSize: false);
      expect(c.installations[1]?.status, InstallationStatus.installed);
      final leftover = await File(
        p.join(profile.installPath, 'mod.txt'),
      ).writeAsString('Keep me');
      expect((await c.overviewStorage(profile, refresh: true)).bytes, 7);
      final manifest = File(p.join(root, 'steamapps', 'appmanifest_1.acf'));
      expect(await manifest.exists(), isTrue);
      await manifest
          .delete(); // Fixture only, simulates Steam's record removal.
      await c.checkInstallation(1, refreshSize: false);
      expect(c.installations[1]?.status, InstallationStatus.missing);
      await c.refreshInstallation(1);
      expect(c.error, isNull);
      expect(
        c.installationNotice,
        'Installation status confirmed: Not Installed.',
      );
      final removedStorage = await c.overviewStorage(profile, refresh: false);
      expect(removedStorage.notInstalled, isTrue);
      expect(removedStorage.bytes, isNull);
      expect(await leftover.readAsString(), 'Keep me');
      expect(await c.requestSteamInstallation(1, uninstall: true), isFalse);
      expect(await c.requestSteamInstallation(1, uninstall: false), isTrue);
      expect(calls.last.method, 'installSteam');
      expect(calls.last.arguments, {'steamId': 1});
      await installed(root, dir: 'New location');
      await c.checkInstallation(1, refreshSize: false);
      expect(c.installations[1]?.status, InstallationStatus.installed);
      expect(c.games.single.appId, 1);
      expect(c.games.single.installPath, endsWith('New location'));
      expect(
        (await c.overviewStorage(c.games.single, refresh: false)).notInstalled,
        isFalse,
      );
      expect(c.games.single.favorite, isTrue);
      expect(c.games.single.hltb?.main, 10);
      expect(c.tracker.toJson(), history);
      expect((await store.load()).sessions, history);
      for (var i = 0; c.sizing.isNotEmpty && i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.sizing, isEmpty);
      await c.shutdown();
    },
  );

  test('an indexed AppID without its manifest remains inconclusive', () async {
    final root = p.join(temp.path, 'Steam');
    await Directory(p.join(root, 'steamapps')).create(recursive: true);
    final escaped = root.replaceAll('\\', '\\\\');
    final index = await File(p.join(root, 'steamapps', 'libraryfolders.vdf'))
        .writeAsString(
          '"libraryfolders" { "0" { "path" "$escaped" "apps" { "1" "10" } } }',
        );
    final service = SteamInstallation(
      SteamScanner(installationRoots: () async => [root]),
    );
    expect(
      (await service.inspect(game(root), [])).status,
      InstallationStatus.unknown,
    );
    await Directory(game(root).installPath).create(recursive: true);
    await index.setLastModified(DateTime(2025, 1, 1, 8));
    final log = File(p.join(root, 'logs', 'content_log.txt'));
    await log.parent.create();
    await log.writeAsString(
      '[2025-01-01 09:00:00] AppID 1 state changed : Uninstalled,\n',
    );
    expect(
      (await service.inspect(game(root), [])).status,
      InstallationStatus.missing,
    );
    await log.writeAsString(
      '[2025-01-01 10:00:00] AppID 1 state changed : Update Required,\n',
      mode: FileMode.append,
    );
    expect(
      (await service.inspect(game(root), [])).status,
      InstallationStatus.unknown,
    );
    await log.writeAsString(
      '[2025-01-01 09:00:00] AppID 1 state changed : Uninstalled,\n',
    );
    await index.setLastModified(DateTime(2025, 1, 1, 10));
    expect(
      (await service.inspect(game(root), [])).status,
      InstallationStatus.unknown,
    );
    await installed(root);
    expect(
      (await service.inspect(game(root), [])).status,
      InstallationStatus.installed,
    );
  });

  test(
    'partial Steam installation stays unknown until a completed manifest',
    () async {
      final root = p.join(temp.path, 'Steam');
      await installed(root);
      final file = File(p.join(root, 'steamapps', 'appmanifest_1.acf'));
      final service = SteamInstallation(
        SteamScanner(installationRoots: () async => [root]),
      );
      await file.writeAsString(
        '"AppState" { "appid" "1" "installdir" "Example" "buildid" "0" "stateflags" "260" }',
      );
      expect(
        (await service.inspect(game(root), [])).status,
        InstallationStatus.unknown,
      );
      await installed(root);
      expect(
        (await service.inspect(game(root), [])).status,
        InstallationStatus.installed,
      );
    },
  );

  testWidgets(
    'cancel closes the named uninstall confirmation without dispatch',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 2600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final profile = game(temp.path);
      final c = VaultController(
        store: LocalStore(temp),
        scanner: SteamScanner(installationRoots: () async => [temp.path]),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
      addTearDown(c.dispose);
      c.games = [profile];
      c.installations[1] = InstallationEvidence(
        InstallationStatus.installed,
        'Fixture',
        installPath: profile.installPath,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailsPage(controller: c, id: 1, onBack: () {}),
          ),
        ),
      );
      await tester.tap(find.text('Game Settings / Installation / Tracking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uninstall Game'));
      await tester.pumpAndSettle();
      expect(find.text('Uninstall Example?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Uninstall Example?'), findsNothing);
      expect(c.managingSteamInstallation, isEmpty);
      expect(c.error, isNull);
      expect(c.games.single, same(profile));
    },
  );

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
