import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'steam_scanner.dart';

enum SteamUpdateState {
  unknown('Unknown'),
  noUpdateRecorded('No pending update recorded'),
  available('Update Available'),
  queued('Queued'),
  downloading('Downloading'),
  updating('Updating'),
  paused('Paused');

  const SteamUpdateState(this.label);
  final String label;
}

class SteamUpdateEvidence {
  const SteamUpdateEvidence(
    this.state,
    this.message, {
    this.recordedAt,
    this.source = 'Steam local metadata',
    this.lastKnown = false,
  });
  static const unknown = SteamUpdateEvidence(
    SteamUpdateState.unknown,
    'No reliable local Steam update state is available.',
  );
  final SteamUpdateState state;
  final String message, source;
  final DateTime? recordedAt;
  final bool lastKnown;
  bool get pending => const [
    SteamUpdateState.available,
    SteamUpdateState.queued,
    SteamUpdateState.paused,
    SteamUpdateState.downloading,
    SteamUpdateState.updating,
  ].contains(state);
  // Presentation only; detailed evidence remains available for diagnosis.
  String? get badge => !lastKnown && pending ? 'Update Available' : null;
  String get summary =>
      '${lastKnown ? 'Last known: ' : ''}${pending ? 'Update Available' : state.label}';
  String get signature => '$state|$message|$source|$recordedAt|$lastKnown';
}

class SteamLogEvent {
  const SteamLogEvent(this.time, this.states);
  final DateTime time;
  final Set<String> states;
}

class SteamLogState {
  SteamLogEvent? app, phase;
}

class _FileCache {
  const _FileCache(this.modified, this.size, this.text);
  final DateTime modified;
  final int size;
  final String text;
}

/// Reads one small manifest per imported AppID/library and a bounded log tail.
/// No Steam writes, private client RPC, remote build comparisons or screenshots.
class SteamUpdateService {
  SteamUpdateService(
    this.scanner, {
    Future<DateTime?> Function()? steamStarted,
    DateTime Function()? clock,
  }) : steamStarted = steamStarted ?? (() async => null),
       clock = clock ?? DateTime.now;
  final SteamScanner scanner;
  final Future<DateTime?> Function() steamStarted;
  final DateTime Function() clock;
  final _cache = <String, _FileCache>{};

  Future<_FileCache?> _read(
    String path, {
    int limit = 128 * 1024,
    bool tail = false,
  }) async {
    try {
      final file = File(path), stat = await FileStat.stat(path);
      if (stat.type != FileSystemEntityType.file ||
          (!tail && stat.size > limit)) {
        _cache.remove(path);
        return null;
      }
      final cached = _cache[path];
      if (tail &&
          cached != null &&
          cached.size == stat.size &&
          cached.modified == stat.modified) {
        return cached;
      }
      final handle = await file.open();
      late List<int> bytes;
      try {
        if (tail && stat.size > limit) {
          await handle.setPosition(stat.size - limit);
        }
        bytes = await handle.read(stat.size.clamp(0, limit));
      } finally {
        await handle.close();
      }
      final after = await file.stat();
      if (after.size != stat.size || after.modified != stat.modified) {
        return null;
      }
      var text = utf8.decode(bytes, allowMalformed: true);
      if (tail && stat.size > limit) {
        final newline = text.indexOf('\n');
        text = newline < 0 ? '' : text.substring(newline + 1);
      }
      final snapshot = _FileCache(stat.modified, stat.size, text);
      if (tail) _cache[path] = snapshot;
      return snapshot;
    } on FileSystemException {
      _cache.remove(path);
      return null;
    }
  }

  static Map<int, SteamLogState> parseLog(String text) {
    final result = <int, SteamLogState>{};
    final pattern = RegExp(
      r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] AppID (\d+) (state changed|App update changed) : (.*)$',
      multiLine: true,
    );
    for (final m in pattern.allMatches(text)) {
      final time = DateTime.tryParse(m[1]!.replaceFirst(' ', 'T'));
      final id = int.tryParse(m[2]!);
      if (time == null || id == null) continue;
      final event = SteamLogEvent(
        time,
        m[4]!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('('))
            .toSet(),
      );
      final record = result.putIfAbsent(id, SteamLogState.new);
      if (m[3] == 'state changed') {
        if (record.app == null || !time.isBefore(record.app!.time)) {
          record.app = event;
        }
      } else {
        if (record.phase == null || !time.isBefore(record.phase!.time)) {
          record.phase = event;
        }
      }
    }
    return result;
  }

  /// Flags are the saved client state, not a comparison with the public branch.
  /// Current-session log transitions supersede older manifests; active download
  /// phases require current-session log evidence, not remaining byte counters.
  static SteamUpdateEvidence classify(
    Map manifest, {
    required DateTime modified,
    required DateTime now,
    DateTime? started,
    SteamLogState? log,
  }) {
    final flags = int.tryParse('${manifest['stateflags']}');
    if (flags == null ||
        flags <= 0 ||
        modified.isAfter(now.add(const Duration(seconds: 2)))) {
      return SteamUpdateEvidence.unknown;
    }
    const known =
        1 |
        2 |
        4 |
        8 |
        16 |
        32 |
        64 |
        128 |
        256 |
        512 |
        1024 |
        2048 |
        4096 |
        8192 |
        16384 |
        32768 |
        65536;
    if ((flags & ~known) != 0 ||
        (flags & (1 | 32 | 128 | 2048 | 4096 | 32768)) != 0) {
      return const SteamUpdateEvidence(
        SteamUpdateState.unknown,
        'Steam reports missing/corrupt files, an installation operation, or an unrecognized state. Open Steam for details.',
      );
    }
    bool valid(SteamLogEvent? e) =>
        e != null &&
        started != null &&
        !e.time.isBefore(started) &&
        !e.time.isAfter(now.add(const Duration(seconds: 2)));
    var required = (flags & 2) != 0,
        queued = (flags & 8) != 0,
        running = (flags & 256) != 0,
        paused = (flags & 512) != 0;
    var recorded = modified;
    var source = 'Steam appmanifest StateFlags (saved client state)';
    final app = log?.app;
    if (valid(app) &&
        !app!.time.isBefore(modified.subtract(const Duration(seconds: 1)))) {
      final states = app.states;
      if (states.any(
        (s) => const [
          'Files Missing',
          'Files Corrupt',
          'Uninstalled',
          'Uninstalling',
          'Moving Folder',
          'Backup Running',
        ].contains(s),
      )) {
        return SteamUpdateEvidence.unknown;
      }
      required = states.contains('Update Required');
      queued = states.contains('Update Queued');
      running = states.contains('Update Running');
      paused = states.contains('Update Paused');
      recorded = app.time;
      source = 'Steam content_log current-session app state';
    }
    final offline = started == null;
    SteamUpdateEvidence evidence(SteamUpdateState state, String message) =>
        SteamUpdateEvidence(
          state,
          message,
          recordedAt: recorded,
          source: source,
          lastKnown: offline,
        );
    if (!required) {
      if (queued || paused || running) return SteamUpdateEvidence.unknown;
      final build = '${manifest['buildid'] ?? ''}',
          target = '${manifest['targetbuildid'] ?? '0'}';
      if (target != '0' && target.isNotEmpty && target != build) {
        return const SteamUpdateEvidence(
          SteamUpdateState.unknown,
          'Target build differs without an explicit Update Required state. A branch change is not proof of a pending update.',
        );
      }
      return evidence(
        SteamUpdateState.noUpdateRecorded,
        'Steam has not recorded a pending update here. This does not guarantee the game is up to date.',
      );
    }
    if ((int.tryParse('${manifest['buildid']}') ?? 0) <= 0) {
      return SteamUpdateEvidence.unknown;
    }
    if (paused && running) return SteamUpdateEvidence.unknown;
    if (paused) {
      return evidence(
        SteamUpdateState.paused,
        'Steam records Update Required and Update Paused. Scheduling details may also exist; no queue position is inferred.',
      );
    }
    final phase = log?.phase;
    if (running && valid(phase) && !phase!.time.isBefore(recorded)) {
      if (phase.states.contains('Stopping') || phase.states.contains('None')) {
        return SteamUpdateEvidence.unknown;
      }
      if (phase.states.contains('Running Update') &&
          phase.states.contains('Downloading')) {
        return SteamUpdateEvidence(
          SteamUpdateState.downloading,
          'Steam explicitly reports the Downloading phase for this update.',
          recordedAt: phase.time,
          source: 'Steam content_log current-session download phase',
        );
      }
    }
    if (running) {
      // Saved running flags can survive a crash; require a current-session event.
      if (source.contains('current-session')) {
        return evidence(
          SteamUpdateState.updating,
          'Steam reports an update running; a download phase is not confirmed.',
        );
      }
      return const SteamUpdateEvidence(
        SteamUpdateState.unknown,
        'Saved Update Running state lacks current-session confirmation.',
      );
    }
    if (queued) {
      return evidence(
        SteamUpdateState.queued,
        'Steam explicitly records Update Queued. No schedule time or queue position is guessed.',
      );
    }
    return evidence(
      SteamUpdateState.available,
      'Steam explicitly records Update Required. Target build, branch, schedule and byte counters alone do not establish this status.',
    );
  }

  Future<Map<int, SteamUpdateEvidence>> refresh(
    List<VaultGame> games,
    List<String> roots,
  ) async {
    final now = clock();
    DateTime? started;
    try {
      started = await steamStarted();
    } catch (_) {
      /* Cannot verify a running client. */
    }
    final steamRoots = await scanner.installationRoots();
    final queue = {
      ...roots,
      ...steamRoots,
      ...games.where((g) => g.isSteam).map((g) => g.libraryPath),
    }.toList();
    final libraries = <String, String>{};
    for (var i = 0; i < queue.length; i++) {
      final normalized = p.normalize(queue[i]);
      final library = p.basename(normalized).toLowerCase() == 'steamapps'
          ? p.dirname(normalized)
          : normalized;
      if (libraries.containsKey(library.toLowerCase())) continue;
      libraries[library.toLowerCase()] = library;
      try {
        queue.addAll(await scanner.discoverPaths(library));
      } catch (_) {
        /* Other configured libraries remain usable. */
      }
    }
    final logs = <int, SteamLogState>{};
    for (final root in steamRoots) {
      final file = await _read(
        p.join(root, 'logs', 'content_log.txt'),
        limit: 1024 * 1024,
        tail: true,
      );
      if (file == null) continue;
      for (final entry in parseLog(file.text).entries) {
        final record = logs.putIfAbsent(entry.key, SteamLogState.new);
        if (entry.value.app != null &&
            (record.app == null ||
                !entry.value.app!.time.isBefore(record.app!.time))) {
          record.app = entry.value.app;
        }
        if (entry.value.phase != null &&
            (record.phase == null ||
                !entry.value.phase!.time.isBefore(record.phase!.time))) {
          record.phase = entry.value.phase;
        }
      }
    }
    final result = <int, SteamUpdateEvidence>{};
    for (final game in games.where((g) => g.isSteam)) {
      final matches = <SteamUpdateEvidence>[];
      for (final library in libraries.values) {
        final file = await _read(
          p.join(library, 'steamapps', 'appmanifest_${game.appId}.acf'),
        );
        if (file == null) continue;
        try {
          final m = ValveKeyValues.parse(file.text)['appstate'];
          if (m is! Map || '${m['appid']}' != '${game.appId}') {
            matches.add(SteamUpdateEvidence.unknown);
            continue;
          }
          final dir = m['installdir']?.toString() ?? '';
          if (dir.isEmpty ||
              p.isAbsolute(dir) ||
              dir.contains('..') ||
              dir.contains('/') ||
              dir.contains('\\') ||
              !await Directory(
                p.join(library, 'steamapps', 'common', dir),
              ).exists()) {
            matches.add(SteamUpdateEvidence.unknown);
            continue;
          }
          matches.add(
            classify(
              m,
              modified: file.modified,
              now: now,
              started: started,
              log: logs[game.appId],
            ),
          );
        } on FormatException {
          matches.add(SteamUpdateEvidence.unknown);
        }
      }
      result[game.appId] = matches.length == 1
          ? matches.single
          : SteamUpdateEvidence.unknown;
    }
    return result;
  }
}
