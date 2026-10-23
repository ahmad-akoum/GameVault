import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/steam_updates.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/ui/components.dart';
import 'package:gamevault/ui/steam_update_indicator.dart';

void main() {
  final now = DateTime(2026, 10, 23, 12), modified = DateTime(2026, 10, 23, 11);
  final started = DateTime(2026, 10, 23, 10);
  Map<String, String> manifest(
    int flags, {
    String target = '11',
    String build = '10',
  }) => {'stateflags': '$flags', 'buildid': build, 'targetbuildid': target};
  SteamUpdateEvidence classify(
    int flags, {
    String target = '11',
    String build = '10',
    String log = '',
    bool running = true,
  }) => SteamUpdateService.classify(
    manifest(flags, target: target, build: build),
    modified: modified,
    now: now,
    started: running ? started : null,
    log: SteamUpdateService.parseLog(log)[1],
  );
  test('explicit installed, required, queued, paused and unknown metadata', () {
    expect(classify(4, target: '10').state, SteamUpdateState.noUpdateRecorded);
    expect(classify(6).state, SteamUpdateState.available);
    expect(classify(14).state, SteamUpdateState.queued);
    expect(classify(518).state, SteamUpdateState.paused);
    expect(
      classify(4).state,
      SteamUpdateState.unknown,
    ); // Target mismatch alone.
    expect(classify(38).badge, isNull); // Missing files is not a new patch.
    expect(classify(6 | (1 << 25)).badge, isNull); // Unknown client flag.
    expect(classify(6 | 256 | 512).state, SteamUpdateState.unknown);
    expect(
      classify(6, build: '0').state,
      SteamUpdateState.unknown,
    ); // An initial installation is not a verified update.
    expect(
      classify(2 | 1024, build: '0').state,
      SteamUpdateState.unknown,
    ); // Initial install.
  });
  test(
    'downloading requires current session and exact phase; stale running flags do not suffice',
    () {
      const log =
          '[2026-10-23 11:01:00] AppID 1 state changed : Update Required,Fully Installed,Update Queued,Update Running,Update Started,\n[2026-10-23 11:01:01] AppID 1 App update changed : Running Update,Downloading,Staging,\n';
      expect(classify(6, log: log).state, SteamUpdateState.downloading);
      expect(
        classify(6, log: log.replaceAll('2026-10-23', '2026-10-22')).state,
        SteamUpdateState.available,
      );
      expect(classify(6 | 256).state, SteamUpdateState.unknown);
      expect(
        classify(
          6,
          log: log.replaceAll('Downloading,Staging', 'Reconfiguring'),
        ).state,
        SteamUpdateState.updating,
      );
      expect(
        classify(
          6,
          log: '$log[2026-10-23 11:01:02] AppID 1 App update changed : None\n',
        ).state,
        SteamUpdateState.unknown,
      );
      expect(
        classify(
          6,
          log:
              '$log[2026-10-23 11:01:03] AppID 1 state changed : Fully Installed,\n',
        ).state,
        SteamUpdateState.unknown,
      ); // Conflicting target, not pending.
    },
  );
  test('closed client retains last-known information without live badges', () {
    for (final flags in [6, 14, 518]) {
      final e = classify(flags, running: false);
      expect(e.lastKnown, true);
      expect(e.badge, isNull);
    }
  });
  test(
    'branch and target mismatch or future metadata never invents a pending update',
    () {
      expect(classify(4, target: '8', build: '10').badge, isNull);
      final beta = {
        ...manifest(6),
        'userconfig': {'betakey': 'experimental'},
      };
      expect(
        SteamUpdateService.classify(
          beta,
          modified: modified,
          now: now,
          started: started,
        ).state,
        SteamUpdateState.available,
      );
      expect(
        SteamUpdateService.classify(
          beta,
          modified: now.add(const Duration(days: 1)),
          now: now,
          started: started,
        ).state,
        SteamUpdateState.unknown,
      );
    },
  );
  test(
    'read-only service handles absent/corrupt/duplicate metadata and refreshes changed files',
    () async {
      final dir = await Directory.systemTemp.createTemp('gamevault_update_');
      try {
        final library = Directory(p.join(dir.path, 'library'));
        final game = VaultGame(
          appId: 1,
          title: 'Fixture',
          installPath: p.join(library.path, 'steamapps', 'common', 'Fixture'),
          libraryPath: library.path,
        );
        final scanner = SteamScanner(installationRoots: () async => []);
        final service = SteamUpdateService(
          scanner,
          steamStarted: () async => started,
          clock: () => DateTime(2100),
        );
        expect(
          (await service.refresh([game], []))[1]!.state,
          SteamUpdateState.unknown,
        );
        await Directory(game.installPath).create(recursive: true);
        final file = File(
          p.join(library.path, 'steamapps', 'appmanifest_1.acf'),
        );
        await file.writeAsString(
          '"AppState" { "appid" "1" "installdir" "Fixture" "StateFlags" "6" "buildid" "10" "TargetBuildID" "11" }',
        );
        expect(
          (await service.refresh([game], []))[1]!.state,
          SteamUpdateState.available,
        );
        await file.writeAsString(
          '"AppState" { "appid" "1" "installdir" "Fixture" "StateFlags" "4" "buildid" "11" "TargetBuildID" "11" }',
        );
        expect(
          (await service.refresh([game], []))[1]!.state,
          SteamUpdateState.noUpdateRecorded,
        );
        final second = p.join(dir.path, 'second-library');
        await Directory(
          p.join(second, 'steamapps', 'common', 'Fixture'),
        ).create(recursive: true);
        await File(
          p.join(second, 'steamapps', 'appmanifest_1.acf'),
        ).writeAsString(await file.readAsString());
        expect(
          (await service.refresh([game], [second]))[1]!.state,
          SteamUpdateState.unknown,
        );
        await file.writeAsString('"AppState" {');
        expect(
          (await service.refresh([game], []))[1]!.state,
          SteamUpdateState.unknown,
        );
        await file.delete();
        expect(
          (await service.refresh([game], []))[1]!.state,
          SteamUpdateState.unknown,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'top-left cover badge and profile preserve Play access and Open in Steam',
    (tester) async {
      final pending = classify(6);
      final g = VaultGame(
        appId: 1,
        title: 'Fixture',
        installPath: 'fixture',
        libraryPath: 'fixture',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 205,
                  height: 350,
                  child: GameTile(
                    game: g,
                    update: pending,
                    onOpen: () {},
                    onFavorite: () {},
                  ),
                ),
                SteamUpdatePanel(
                  evidence: pending,
                  onOpen: () => WindowsGames.openSteam(1),
                ),
              ],
            ),
          ),
        ),
      );
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
      expect(find.byType(SteamUpdateBadge), findsOneWidget);
      final positioned = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byType(SteamUpdateBadge),
              matching: find.byType(Positioned),
            )
            .first,
      );
      expect(positioned.top, 7);
      expect(positioned.left, 7);
      await tester.tap(find.text('Open in Steam'));
      await tester.pump();
      expect(calls.single.method, 'openSteam');
      expect(calls.single.arguments, {'steamId': 1});
      for (final e in [
        SteamUpdateEvidence.unknown,
        classify(4, target: '10'),
        classify(6, running: false),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 205,
                height: 350,
                child: GameTile(
                  game: g,
                  update: e,
                  onOpen: () {},
                  onFavorite: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.byType(SteamUpdateBadge), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
