import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_installation.dart';
import 'package:gamevault/services/steam_updates.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/details_page.dart';
import 'package:gamevault/ui/components.dart';
import 'package:gamevault/ui/tracking_controls.dart';
import 'package:gamevault/ui/steam_update_indicator.dart';
import 'services_test.dart' show TestMetadata, TestHltb;

// Records Play dispatch without launching a real game or starting the monitor.
class ActionTestController extends VaultController {
  ActionTestController(Directory dir)
    : super(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: TestHltb(),
      );
  final launched = <int>[];
  int installationChecks = 0;
  InstallationEvidence? nextInstallation;
  @override
  Future<void> checkInstallation(int id, {bool refreshSize = true}) async {
    installationChecks++;
    if (nextInstallation case final evidence?) {
      installations[id] = evidence;
      notifyListeners();
    }
  }

  @override
  Future<void> launch(int id) async {
    launched.add(id);
  }
}

void main() {
  testWidgets(
    'shared cover cards show verified absence and preserve personal status',
    (tester) async {
      final game = VaultGame(
        appId: 1,
        title: 'Fixture',
        installPath: 'x',
        libraryPath: 'x',
        status: GameStatus.onHold,
      );
      Future<void> render(InstallationStatus status) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VaultGrid(
                games: [game],
                onOpen: (_) {},
                onFavorite: (_) {},
                updates: const {
                  1: SteamUpdateEvidence(SteamUpdateState.available, 'Fixture'),
                },
                installations: {1: InstallationEvidence(status, 'Fixture')},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(InstallationStatus.missing);
      expect(find.text('Not Installed'), findsOneWidget);
      expect(find.text('On Hold'), findsOneWidget);
      expect(find.byType(SteamUpdateBadge), findsNothing);
      await render(InstallationStatus.unknown);
      expect(find.text('Not Installed'), findsNothing);
      expect(find.byType(SteamUpdateBadge), findsOneWidget);
      expect(find.text('On Hold'), findsOneWidget);
    },
  );
  testWidgets('focus and visible timer update a Steam profile', (tester) async {
    final c = ActionTestController(Directory.systemTemp);
    addTearDown(c.dispose);
    c.games = [
      VaultGame(appId: 1, title: 'Fixture', installPath: 'x', libraryPath: 'x'),
    ];
    c.nextInstallation = const InstallationEvidence(
      InstallationStatus.installed,
      'Fixture',
      installPath: 'x',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => DetailsPage(controller: c, id: 1, onBack: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    c.nextInstallation = const InstallationEvidence(
      InstallationStatus.missing,
      'Fixture',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Install via Steam'), findsOneWidget);
    final checks = c.installationChecks;
    c.nextInstallation = const InstallationEvidence(
      InstallationStatus.installed,
      'Fixture',
      installPath: 'x',
    );
    await tester.pump(const Duration(seconds: 12));
    expect(c.installationChecks, checks + 1);
    expect(find.text('Play Game'), findsOneWidget);
    expect(
      find.textContaining('Steam has not confirmed a change'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'verified transitions replace launch in place, unknown and completed restore it; external actions stay visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 2000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('profile_actions_'),
      ))!;
      final c = (await tester.runAsync(() async {
        final controller = ActionTestController(dir);
        await controller.initialize();
        return controller;
      }))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Synthetic',
          installPath: dir.path,
          libraryPath: dir.path,
        ),
      ];
      c.installations[1] = InstallationEvidence(
        InstallationStatus.installed,
        'Fixture',
        installPath: dir.path,
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
      Future<void> render(
        SteamUpdateEvidence evidence, {
        bool dark = false,
      }) async {
        c.steamUpdates[1] = evidence;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: DetailsPage(controller: c, id: 1, onBack: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(SteamUpdateEvidence.unknown);
      final playPosition = tester.getTopLeft(find.text('Play Game'));
      expect(find.text('Open in Steam'), findsOneWidget);
      expect(find.text('Open File Location'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Open in Steam')).dy,
        tester.getTopLeft(find.text('Open File Location')).dy,
      );
      for (final state in [
        SteamUpdateState.available,
        SteamUpdateState.queued,
        SteamUpdateState.paused,
        SteamUpdateState.downloading,
        SteamUpdateState.updating,
      ]) {
        await render(SteamUpdateEvidence(state, 'Verified fixture.'));
        expect(find.text('Play Game'), findsNothing);
        expect(find.byType(SteamUpdateAction), findsOneWidget);
        expect(find.text('Update Available'), findsOneWidget);
        expect(c.steamUpdates[1]!.badge, 'Update Available');
        expect(c.steamUpdates[1]!.state, state);
        for (final label in ['Queued', 'Paused', 'Downloading', 'Updating']) {
          expect(find.text(label), findsNothing);
        }
        expect(
          tester.getTopLeft(find.byType(SteamUpdateAction)).dy,
          closeTo(playPosition.dy - 12, 16),
        );
        await tester.tap(find.byType(SteamUpdateAction));
        expect(c.pendingLaunches, isEmpty);
        await tester.pump();
        expect(calls.single.method, 'openSteam');
        expect(calls.single.arguments, {'steamId': 1});
        expect(c.launched, isEmpty);
        expect(c.error, isNull);
        calls.clear();
        expect(
          find.text(
            'Opens this game in Steam. Start the update there manually.',
          ),
          findsOneWidget,
        );
        expect(find.text('Open in Steam'), findsOneWidget);
        expect(find.text('Open File Location'), findsOneWidget);
      }
      for (final evidence in [
        const SteamUpdateEvidence(
          SteamUpdateState.noUpdateRecorded,
          'Completed fixture.',
        ),
        const SteamUpdateEvidence(
          SteamUpdateState.available,
          'Old evidence.',
          lastKnown: true,
        ),
        SteamUpdateEvidence.unknown,
      ]) {
        await render(evidence);
        expect(find.text('Play Game'), findsOneWidget);
        expect(find.byType(SteamUpdateAction), findsNothing);
      }
      await tester.tap(find.text('Play Game'));
      expect(c.launched, [1]);
      expect(calls, isEmpty);
      await tester.tap(find.text('Open in Steam'));
      await tester.pump();
      expect(calls.single.method, 'openSteam');
      expect(calls.single.arguments, {'steamId': 1});
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsGames.channel, (call) async {
            calls.add(call);
            throw PlatformException(code: 'steam_unavailable');
          });
      await render(
        const SteamUpdateEvidence(
          SteamUpdateState.available,
          'Verified fixture.',
        ),
      );
      await tester.tap(find.byType(SteamUpdateAction));
      await tester.pump();
      expect(c.error, contains('could not be opened'));
      expect(c.launched, [1]);
      expect(calls.single.method, 'openSteam');
      expect(c.pendingLaunches, isEmpty);
      for (final size in ProfileSize.values) {
        c.settings = c.settings.copy(profileSize: size);
        tester.view.physicalSize = const Size(360, 700);
        for (final dark in [false, true]) {
          await render(
            const SteamUpdateEvidence(
              SteamUpdateState.downloading,
              'Verified fixture.',
            ),
            dark: dark,
          );
          await tester.scrollUntilVisible(
            find.text('Open File Location'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Open in Steam'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.physicalSize = const Size(1280, 2600);
      await render(SteamUpdateEvidence.unknown);
      await tester.ensureVisible(
        find.text('Game Settings / Installation / Tracking'),
      );
      await tester.tap(find.text('Game Settings / Installation / Tracking'));
      await tester.pumpAndSettle();
      expect(find.text('Game Update Center'), findsOneWidget);
      expect(find.text('Refresh update status'), findsOneWidget);
      expect(find.text('Update diagnostics'), findsNothing);
      c.installations[1] = const InstallationEvidence(
        InstallationStatus.missing,
        'Fixture',
      );
      await render(
        const SteamUpdateEvidence(SteamUpdateState.available, 'Stale fixture'),
      );
      expect(find.text('Install via Steam'), findsOneWidget);
      expect(find.text('Installation: Not Installed'), findsOneWidget);
      expect(find.text('Game Update Center'), findsNothing);
      expect(find.text('Open EXE Location'), findsNothing);
      expect(find.text('Open in Steam'), findsOneWidget);
      c.installations[1] = const InstallationEvidence(
        InstallationStatus.unknown,
        'Fixture',
      );
      await render(
        const SteamUpdateEvidence(SteamUpdateState.available, 'Stale fixture'),
      );
      expect(find.byType(SteamUpdateAction), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Play Game'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
      c.installations[1] = InstallationEvidence(
        InstallationStatus.installed,
        'Fixture',
        installPath: dir.path,
      );
      await render(
        const SteamUpdateEvidence(
          SteamUpdateState.noUpdateRecorded,
          'Fixture',
          matchesRecordedTarget: true,
        ),
      );
      expect(find.text('Up to Date'), findsOneWidget);
      expect(find.text('Game Update Center'), findsOneWidget);
      expect(find.text('Play Game'), findsOneWidget);

      // A local game must ignore any accidental Steam evidence.
      c.games = [
        VaultGame(
          appId: -1,
          title: 'Local',
          installPath: dir.path,
          libraryPath: '',
        ),
      ];
      c.steamUpdates[-1] = const SteamUpdateEvidence(
        SteamUpdateState.available,
        'Not applicable.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackingControls(controller: c, game: c.games.single),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Play Game'), findsOneWidget);
      expect(find.byType(SteamUpdateAction), findsNothing);
      expect(c.tracker.sessions, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
}
