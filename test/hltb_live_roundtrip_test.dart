// Explicit opt-in live integration test; no personal data is read.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/hltb_provider.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/state/vault_controller.dart';
import 'services_test.dart' show TestMetadata;

void main() {
  test(
    'live HLTB search, manual selection, refresh and saved-match persistence',
    () async {
      final dir = await Directory.systemTemp.createTemp('gamevault_live_hltb_');
      final provider = WebsiteHltbProvider();
      final c = VaultController(
        store: LocalStore(dir),
        scanner: SteamScanner(installationRoots: () async => []),
        metadata: TestMetadata(),
        hltb: provider,
      );
      await c.initialize();
      try {
        c.games = [
          VaultGame(
            appId: 1245620,
            title: 'Local test entry',
            installPath: 'fixture',
            libraryPath: 'fixture',
          ),
        ];
        await c.lookup(1245620, query: 'Elden Ring');
        expect(
          c.games.single.hltbState,
          HltbState.ambiguous,
          reason: c.games.single.hltbMessage,
        );
        final entry = c.games.single.candidates.singleWhere(
          (e) => e.title == 'Elden Ring',
        );
        expect(entry.main, greaterThan(0));
        expect(entry.extras, greaterThan(0));
        expect(entry.complete, greaterThan(0));
        await c.selectMatch(1245620, entry);
        final first = c.games.single.hltbUpdated!;
        await c.lookup(1245620);
        expect(
          c.games.single.hltbState,
          HltbState.matched,
          reason: c.games.single.hltbMessage,
        );
        expect(c.games.single.hltb!.id, entry.id);
        expect(c.games.single.hltbUpdated!.isBefore(first), false);
        final saved = await c.store.load();
        expect(saved.games.single.hltb!.id, entry.id);
        expect(saved.games.single.hltb!.main, greaterThan(0));
      } finally {
        await c.shutdown();
        c.dispose();
        provider.client.close();
        await dir.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('GAMEVAULT_LIVE_HLTB'),
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
