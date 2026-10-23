import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'package:gamevault/ui/details_page.dart';
import 'package:gamevault/ui/activity_pages.dart';
import 'package:gamevault/services/steam_updates.dart';
import 'package:gamevault/ui/steam_update_indicator.dart';
import 'services_test.dart' show TestMetadata, TestHltb;
import 'session_presentation_test.dart' show fixture;

void main() {
  testWidgets(
    'latest two sessions expand and collapse without changing records; narrow settings remain accessible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gamevault_profile_'),
      ))!;
      final c = (await tester.runAsync(() async {
        final controller = VaultController(
          store: LocalStore(dir),
          scanner: SteamScanner(installationRoots: () async => []),
          metadata: TestMetadata(),
          hltb: TestHltb(),
        );
        await controller.initialize();
        return controller;
      }))!;
      c.games = [
        VaultGame(
          appId: 1,
          title: 'Example',
          installPath: dir.path,
          libraryPath: dir.path,
        ),
      ];
      c.steamUpdates[1] = const SteamUpdateEvidence(
        SteamUpdateState.available,
        'Steam explicitly records Update Required.',
      );
      c.tracker.sessions.addAll([
        fixture(61, 40),
        fixture(120, 60),
        fixture(180, 120),
      ]);
      final before = jsonEncode(c.tracker.toJson());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailsPage(controller: c, id: 1, onBack: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Play game'), findsNothing);
      expect(find.byType(SteamUpdateAction), findsOneWidget);
      expect(find.text('Open in Steam'), findsOneWidget);
      expect(find.byType(SessionRow), findsNWidgets(2));
      await tester.tap(find.text('View all sessions'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionRow), findsNWidgets(3));
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionRow), findsNWidgets(2));
      tester.view.physicalSize = const Size(360, 700);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Game Settings / Installation / Tracking'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Game Settings / Installation / Tracking'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Refresh Installation'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open EXE Location'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(jsonEncode(c.tracker.toJson()), before);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.shutdown();
        c.dispose();
        await dir.delete(recursive: true);
      });
    },
  );
}
