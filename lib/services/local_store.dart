import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game.dart';

class StorageFailure implements Exception {
  const StorageFailure(this.message);
  final String message;
}

class VaultSnapshot {
  const VaultSnapshot(this.games, this.settings, {this.recovered = false});
  final List<VaultGame> games;
  final VaultSettings settings;
  final bool recovered;
}

/// Small, versioned local document. Serialized writes, flushed staging file,
/// and previous-good backup keep interrupted saves recoverable on Windows.
class LocalStore {
  LocalStore(this.directory);
  final Directory directory;
  Future<void> _tail = Future.value();
  RandomAccessFile? _lock;
  File get file => File(p.join(directory.path, 'vault.json'));
  File get backup => File('${file.path}.bak');
  Directory get artwork => Directory(p.join(directory.path, 'artwork'));
  Future<void> acquireLock() async {
    await directory.create(recursive: true);
    _lock = await File(
      p.join(directory.path, 'vault.lock'),
    ).open(mode: FileMode.append);
    try {
      await _lock!.lock(FileLock.exclusive);
    } catch (_) {
      await _lock!.close();
      _lock = null;
      throw const StorageFailure(
        'GameVault is already open, or its data folder is not writable.',
      );
    }
  }

  Future<void> close() async {
    await _tail;
    await _lock?.unlock();
    await _lock?.close();
    _lock = null;
  }

  Future<VaultSnapshot> load() async {
    await directory.create(recursive: true);
    for (final source in [file, backup]) {
      if (!await source.exists()) {
        continue;
      }
      try {
        final j =
            jsonDecode(await source.readAsString()) as Map<String, dynamic>;
        if (j['version'] != 1) {
          throw const FormatException('Unsupported storage version');
        }
        final games = (j['games'] as List).map((e) {
          final data = Map<String, dynamic>.from(e);
          for (final key in ['coverPath', 'heroPath']) {
            final path = data[key];
            if (path is String) {
              data[key] = p.isAbsolute(path)
                  ? path
                  : p.join(directory.path, path);
            }
          }
          return VaultGame.fromJson(data);
        }).toList();
        if (games.map((g) => g.appId).toSet().length != games.length) {
          throw const FormatException('Duplicate IDs');
        }
        return VaultSnapshot(
          games,
          VaultSettings.fromJson(Map<String, dynamic>.from(j['settings'])),
          recovered: source.path == backup.path,
        );
      } catch (e) {
        stderr.writeln('Storage read failed (${source.path}): $e');
      }
    }
    if (await file.exists() || await backup.exists()) {
      throw const StorageFailure(
        'Your library file could not be read. It has been preserved. Restore vault.json from a backup before continuing.',
      );
    }
    return const VaultSnapshot([], VaultSettings());
  }

  Future<void> save(List<VaultGame> games, VaultSettings settings) {
    final encoded = jsonEncode({
      'version': 1,
      'games': games.map((g) {
        final data = g.toJson();
        for (final key in ['coverPath', 'heroPath']) {
          final path = data[key];
          if (path is String && p.isWithin(directory.path, path)) {
            data[key] = p.relative(path, from: directory.path);
          }
        }
        return data;
      }).toList(),
      'settings': settings.toJson(),
    });
    final result = _tail.then((_) async {
      try {
        await directory.create(recursive: true);
        final staging = File('${file.path}.pending');
        await staging.writeAsString(encoded, flush: true);
        if (await file.exists()) {
          // Only overwrite the backup when the current document is readable.
          try {
            final j = jsonDecode(await file.readAsString());
            if (j is Map && j['version'] == 1) {
              final previousGames = (j['games'] as List)
                  .map((e) => VaultGame.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
              VaultSettings.fromJson(Map<String, dynamic>.from(j['settings']));
              if (previousGames.map((g) => g.appId).toSet().length !=
                  previousGames.length) {
                throw const FormatException('Duplicate IDs');
              }
              await file.copy(backup.path);
            }
          } catch (_) {
            /* Preserve existing known-good backup. */
          }
          await file.delete();
        }
        await staging.rename(file.path);
      } catch (e) {
        stderr.writeln('Storage save failed: $e');
        throw const StorageFailure(
          'Changes could not be saved. Check free disk space and folder permissions, then retry.',
        );
      }
    });
    _tail = result.catchError((Object _) {});
    return result;
  }
}
