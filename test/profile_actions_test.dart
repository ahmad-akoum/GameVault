import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_updates.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/details_page.dart';
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
  @override
  Future<void> launch(int id) async {
    launched.add(id);
  }
}

void main() {
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
      final playPosition = tester.getTopLeft(find.text('Play game'));
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
        expect(find.text('Play game'), findsNothing);
        expect(find.byType(SteamUpdateAction), findsOneWidget);
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
          state == SteamUpdateState.available ? findsOneWidget : findsNothing,
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
        expect(find.text('Play game'), findsOneWidget);
        expect(find.byType(SteamUpdateAction), findsNothing);
      }
      await tester.tap(find.text('Play game'));
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
      expect(find.text('Play game'), findsOneWidget);
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
