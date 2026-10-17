import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import '../services/local_store.dart';
import '../services/steam_scanner.dart';
import '../services/hltb_provider.dart';
import '../services/metadata_provider.dart';
import '../services/windows_games.dart';
import '../services/session_tracker.dart';

class VaultController extends ChangeNotifier {
  VaultController({
    required this.store,
    required this.scanner,
    required this.metadata,
    required this.hltb,
    this.platform,
  });
  final LocalStore store;
  final SteamScanner scanner;
  final GameMetadataProvider metadata;
  final HltbProvider hltb;
  final GamePlatform? platform;
  final SessionTracker tracker = SessionTracker();
  final Stopwatch _clock = Stopwatch();
  Timer? _monitor;
  Future<void>? _poll;
  bool _closing = false;
  int _lastCheckpoint = 0;
  String? trackingError;
  final Map<int, int> pendingLaunches = {};
  int played(int id) => tracker.total(id, active: settings.activityAdjusted);
  bool running(int id) => tracker.current(id) != null;
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
      tracker.load(snapshot.sessions);
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
    if (!storageBlocked && platform != null) {
      _clock.start();
      _monitor = Timer.periodic(const Duration(seconds: 2), (_) => pollGames());
    }
    notifyListeners();
  }

  Future<bool> _commit(List<VaultGame> next, VaultSettings nextSettings) async {
    if (storageBlocked) {
      return false;
    }
    try {
      await store.save(next, nextSettings, sessions: tracker.toJson());
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
            coverPath: current.artwork?.coverChosen == true
                ? current.coverPath
                : current.coverPath ?? enriched.coverPath,
            heroPath: current.artwork?.heroChosen == true
                ? current.heroPath
                : current.heroPath ?? enriched.heroPath,
            release: enriched.release,
            developer: enriched.developer,
            publisher: enriched.publisher,
            genres: enriched.genres,
            metadataMessage: enriched.metadataMessage,
          ),
        );
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
          coverPath: g.artwork?.coverChosen == true
              ? g.coverPath
              : g.coverPath ?? e.coverPath,
          heroPath: g.artwork?.heroChosen == true
              ? g.heroPath
              : g.heroPath ?? e.heroPath,
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

  Future<bool> applyArtwork(
    int id, {
    required bool cover,
    required String? path,
    required bool contained,
    List<String> choices = const [],
  }) async {
    var saved = false;
    await _mutate(() async {
      final g = game(id);
      if (g == null || _closing) return;
      final old =
          g.artwork ??
          ArtworkPreferences(
            originalCover: g.coverPath,
            originalHero: g.profileArtworkPath,
          );
      final preferences = ArtworkPreferences(
        coverChosen: cover || old.coverChosen,
        heroChosen: !cover || old.heroChosen,
        originalCover: old.originalCover,
        originalHero: old.originalHero,
        covers: cover
            ? {...old.covers, ...choices, ?path}.toList()
            : old.covers,
        heroes: cover
            ? old.heroes
            : {...old.heroes, ...choices, ?path}.toList(),
        coverContained: cover ? contained : old.coverContained,
        heroContained: cover ? old.heroContained : contained,
      );
      final changed = g.copy(
        artwork: preferences,
        coverPath: cover ? path : null,
        heroPath: cover ? null : path,
        clearCover: cover && path == null,
        clearHero: !cover && path == null,
      );
      saved = await _commit(
        games.map((item) => item.appId == id ? changed : item).toList(),
        settings,
      );
    });
    return saved;
  }

  Future<void> launch(int id) async {
    final g = game(id);
    if (g == null || running(id) || pendingLaunches.containsKey(id)) return;
    if (platform == null) {
      error = 'Game launching is available on Windows.';
      notifyListeners();
      return;
    }
    pendingLaunches[id] = _clock.elapsed.inSeconds + 120;
    notifyListeners();
    try {
      await platform!.launch(g);
      if (!settings.trackingEnabled) {
        pendingLaunches.remove(id);
        notifyListeners();
        return;
      }
      await pollGames();
    } catch (_) {
      pendingLaunches.remove(id);
      error =
          'Could not launch ${g.title}. Check its installation, executable and Steam availability.';
      notifyListeners();
    }
  }

  Future<void> pollGames() {
    if (_closing || storageBlocked || platform == null) return Future.value();
    return _poll ??= _sampleGames().whenComplete(() => _poll = null);
  }

  Future<void> _sampleGames() async {
    try {
      final sample = settings.trackingEnabled
          ? await platform!.sample(List.of(games))
          : WindowsSample([], 0);
      await _mutate(() async {
        if (_closing) return;
        final hadError = trackingError != null;
        final pendingBefore = pendingLaunches.length;
        final before = tracker.sessions.length;
        final openBefore = tracker.sessions.where((s) => s.open).length;
        tracker.sample(
          now: DateTime.now(),
          monotonicSeconds: _clock.elapsed.inSeconds,
          games: sample.games.where((g) => game(g.id) != null).toList(),
          idleSeconds: sample.idleSeconds,
          idleThreshold: settings.idleThreshold,
          focusGrace: settings.focusGrace,
        );
        trackingError = null;
        for (final id in pendingLaunches.keys.toList()) {
          if (running(id)) {
            pendingLaunches.remove(id);
          } else if (_clock.elapsed.inSeconds >= pendingLaunches[id]!) {
            pendingLaunches.remove(id);
            error =
                'No game process was confirmed. If it is running, choose its exact tracking executable on the detail page.';
          }
        }
        final elapsed = _clock.elapsed.inSeconds;
        if (before != tracker.sessions.length ||
            openBefore != tracker.sessions.where((s) => s.open).length ||
            (tracker.sessions.any((s) => s.open) &&
                elapsed - _lastCheckpoint >= 15)) {
          if (await _commit(games, settings)) _lastCheckpoint = elapsed;
        }
        if (hadError ||
            pendingBefore != pendingLaunches.length ||
            before != tracker.sessions.length ||
            openBefore > 0 ||
            tracker.sessions.any((s) => s.open)) {
          notifyListeners();
        }
      });
    } catch (_) {
      tracker.closeAll('Monitoring unavailable');
      trackingError =
          'Game monitoring is unavailable. Unobserved time is not counted.';
      notifyListeners();
    }
  }

  Future<void> addManual(String title, String executable) => _mutate(() async {
    final path = p.normalize(executable);
    if (title.trim().isEmpty ||
        !p.isAbsolute(path) ||
        !path.toLowerCase().endsWith('.exe') ||
        !await File(path).exists()) {
      error = 'Choose an existing .exe file and enter a game name.';
      notifyListeners();
      return;
    }
    if (games.any(
      (g) => g.executablePath?.toLowerCase() == path.toLowerCase(),
    )) {
      error = 'This executable is already in your library.';
      notifyListeners();
      return;
    }
    // Removed games may still have history. Never reuse their identity.
    final lowest = [
      ...games.map((g) => g.appId),
      ...tracker.sessions.map((s) => s.gameId),
    ].fold<int>(0, (id, candidate) => candidate < id ? candidate : id);
    await _commit([
      ...games,
      VaultGame(
        appId: lowest - 1,
        title: title.trim(),
        installPath: p.dirname(path),
        libraryPath: p.dirname(path),
        executablePath: path,
      ),
    ], settings);
  });

  Future<void> saveCollection(String name, {String? previous}) => _mutate(
    () async {
      final clean = name.trim();
      if (clean.isEmpty ||
          clean.length > 60 ||
          settings.collections.any(
            (c) => c != previous && c.toLowerCase() == clean.toLowerCase(),
          )) {
        error = 'Use a unique collection name between 1 and 60 characters.';
        notifyListeners();
        return;
      }
      final names = [...settings.collections.where((n) => n != previous), clean]
        ..sort();
      final next = games
          .map(
            (g) => g.copy(
              collections: g.collections
                  .map((n) => n == previous ? clean : n)
                  .toList(),
            ),
          )
          .toList();
      await _commit(next, settings.copy(collections: names));
    },
  );
  Future<void> deleteCollection(String name) => _mutate(() async {
    await _commit(
      games
          .map(
            (g) => g.copy(
              collections: g.collections.where((n) => n != name).toList(),
            ),
          )
          .toList(),
      settings.copy(
        collections: settings.collections.where((n) => n != name).toList(),
      ),
    );
  });

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
    _closing = true;
    _monitor?.cancel();
    await _poll;
    await _mutate(() async {
      final hasOpen = tracker.sessions.any((s) => s.open);
      tracker.closeAll('GameVault closed');
      if (hasOpen) await _commit(games, settings);
    });
    storageBlocked = true;
    await _mutationTail;
    await store.close();
  }
}
