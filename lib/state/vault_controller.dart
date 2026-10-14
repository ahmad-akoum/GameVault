import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/game.dart';
import '../services/local_store.dart';
import '../services/steam_scanner.dart';
import '../services/hltb_provider.dart';
import '../services/metadata_provider.dart';

class VaultController extends ChangeNotifier {
  VaultController({
    required this.store,
    required this.scanner,
    required this.metadata,
    required this.hltb,
  });
  final LocalStore store;
  final SteamScanner scanner;
  final GameMetadataProvider metadata;
  final HltbProvider hltb;
  List<VaultGame> games = [];
  VaultSettings settings = const VaultSettings();
  List<SteamGame> detected = [];
  List<String> scanWarnings = [];
  List<String> scannedPaths = [];
  bool scanning = false, importing = false, initialized = false;
  bool storageBlocked = false;
  String? error, fatalError;
  String activity = '';
  final Set<int> busy = {};
  Future<void> _lookupTail = Future.value();
  VaultGame? game(int id) => games.where((g) => g.appId == id).firstOrNull;
  Future<void> initialize() async {
    try {
      await store.acquireLock();
      final snapshot = await store.load();
      games = snapshot.games;
      settings = snapshot.settings;
      if (snapshot.recovered) {
        error = 'Your library was recovered from its previous saved version.';
      }
    } on StorageFailure catch (e) {
      fatalError = e.message;
      storageBlocked = true;
    } catch (e) {
      stderr.writeln(e);
      fatalError =
          'GameVault could not open its local data folder. Check permissions.';
      storageBlocked = true;
    }
    initialized = true;
    notifyListeners();
  }

  Future<bool> _commit(List<VaultGame> next, VaultSettings nextSettings) async {
    if (storageBlocked) {
      return false;
    }
    try {
      await store.save(next, nextSettings);
      games = next;
      settings = nextSettings;
      notifyListeners();
      return true;
    } on StorageFailure catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> setSettings(VaultSettings value) => _mutate(() async {
    await _commit(games, value);
  });
  // Serialize all mutations; background enrichments read the latest state only
  // after entering this queue, so favorite/status edits cannot be overwritten.
  Future<void> _mutationTail = Future.value();
  Future<void> _mutate(Future<void> Function() action) {
    final result = _mutationTail.then((_) => action());
    _mutationTail = result.catchError((Object e) {
      stderr.writeln(e);
    });
    return result;
  }

  Future<void> update(int id, VaultGame Function(VaultGame) change) =>
      _mutate(() async {
        if (game(id) == null) {
          return;
        }
        await _commit(
          games.map((g) => g.appId == id ? change(g) : g).toList(),
          settings,
        );
      });
  Future<void> remove(int id) => _mutate(() async {
    await _commit(games.where((g) => g.appId != id).toList(), settings);
  });
  Future<void> scan() async {
    if (scanning) {
      return;
    }
    scanning = true;
    error = null;
    detected = [];
    scanWarnings = [];
    scannedPaths = [];
    notifyListeners();
    try {
      final result = await scanner.scan(settings.paths);
      detected = result.games;
      scanWarnings = result.warnings;
      scannedPaths = result.paths;
    } on ScanFailure catch (e) {
      error = e.message;
    } catch (e) {
      stderr.writeln(e);
      error =
          'The Steam libraries could not be scanned. Check that the drives are available.';
    }
    scanning = false;
    notifyListeners();
  }

  Future<void> importGames(Set<int> ids) async {
    if (importing) {
      return;
    }
    importing = true;
    notifyListeners();
    final chosen = detected
        .where((d) => ids.contains(d.appId) && game(d.appId) == null)
        .toList();
    await _mutate(() async {
      await _commit([
        ...games,
        ...chosen.where((d) => game(d.appId) == null).map(VaultGame.fromSteam),
      ], settings);
    });
    for (final d in chosen) {
      if (game(d.appId) == null) {
        continue;
      }
      busy.add(d.appId);
      activity = 'Fetching information for ${d.name}';
      notifyListeners();
      try {
        final enriched = await metadata.enrich(game(d.appId)!);
        await update(
          d.appId,
          (current) => current.copy(
            title: enriched.title,
            coverPath: enriched.coverPath,
            heroPath: enriched.heroPath,
            release: enriched.release,
            developer: enriched.developer,
            publisher: enriched.publisher,
            genres: enriched.genres,
            metadataMessage: enriched.metadataMessage,
          ),
        );
        await lookup(d.appId);
      } catch (e) {
        stderr.writeln('Import enrichment: $e');
      }
      busy.remove(d.appId);
      notifyListeners();
    }
    importing = false;
    activity = '';
    notifyListeners();
  }

  Future<void> refreshMetadata(int id) async {
    if (busy.contains(id) || game(id) == null) {
      return;
    }
    busy.add(id);
    notifyListeners();
    try {
      final e = await metadata.enrich(game(id)!);
      await update(
        id,
        (g) => g.copy(
          title: e.title,
          coverPath: e.coverPath,
          heroPath: e.heroPath,
          release: e.release,
          developer: e.developer,
          publisher: e.publisher,
          genres: e.genres,
          metadataMessage: e.metadataMessage,
        ),
      );
    } finally {
      busy.remove(id);
      notifyListeners();
    }
  }

  Future<void> lookup(int id, {String? query}) {
    final result = _lookupTail.then((_) => _lookup(id, query));
    _lookupTail = result.catchError((Object e) {
      stderr.writeln(e);
    });
    return result;
  }

  Future<void> _lookup(int id, String? query) async {
    if (game(id) == null) {
      return;
    }
    await update(id, (g) => g.copy(hltbState: HltbState.loading));
    final original = game(id);
    if (original == null) {
      return;
    }
    try {
      final results = HltbMatcher.rank(
        original.title,
        await hltb.search(query ?? original.title),
      );
      final match = HltbMatcher.confidentMatch(original.title, id, results);
      await update(
        id,
        (g) => g.copy(
          hltbState: match != null
              ? HltbState.matched
              : results.isEmpty
              ? HltbState.noMatch
              : HltbState.ambiguous,
          hltb: match,
          candidates: results,
          hltbUpdated: match != null ? DateTime.now() : null,
          hltbMessage: match != null
              ? 'Matched to ${match.title}'
              : results.isEmpty
              ? 'No matching game found. Try a shorter or alternate title.'
              : 'Choose the correct game below.',
        ),
      );
    } on HltbFailure catch (e) {
      await update(
        id,
        (g) => g.copy(hltbState: e.state, hltbMessage: e.message),
      );
    } catch (e) {
      stderr.writeln(e);
      await update(
        id,
        (g) => g.copy(
          hltbState: HltbState.unavailable,
          hltbMessage: 'HowLongToBeat is unavailable. Try again later.',
        ),
      );
    }
  }

  Future<void> selectMatch(int id, HltbEntry entry) => update(
    id,
    (g) => g.copy(
      hltb: entry,
      hltbState: HltbState.matched,
      candidates: [],
      hltbUpdated: DateTime.now(),
      hltbMessage: 'Selected ${entry.title}',
    ),
  );
  void dismissError() {
    error = null;
    notifyListeners();
  }

  Future<void> shutdown() async {
    storageBlocked = true;
    await _mutationTail;
    await store.close();
  }
}
