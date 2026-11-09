import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/steam_playtime.dart';
import '../models/playtime_reconciliation.dart';

class SteamPlaytimeStorageFailure implements Exception {
  const SteamPlaytimeStorageFailure();
  @override
  String toString() =>
      'Steam playtime data could not be saved or read; existing data was preserved.';
}

/// One sidecar per vault/profile. Never reads or writes vault.json or sessions.
class SteamPlaytimeData {
  SteamPlaytimeData({
    this.confirmedAccount,
    Map<String, SteamPlaytimeSnapshot> latest = const {},
    Map<String, SteamPlaytimeSnapshot> lastKnown = const {},
    Map<String, List<PlaytimeBaseline>> baselines = const {},
    this.recoveredFromBackup = false,
  }) : latest = Map.unmodifiable(latest),
       lastKnown = Map.unmodifiable(lastKnown),
       baselines = Map.unmodifiable(
         baselines.map(
           (key, values) =>
               MapEntry(key, List<PlaytimeBaseline>.unmodifiable(values)),
         ),
       );
  final SteamPlaytimeAccount? confirmedAccount;
  final Map<String, SteamPlaytimeSnapshot> latest, lastKnown;
  final Map<String, List<PlaytimeBaseline>> baselines;
  final bool recoveredFromBackup;

  Map<String, dynamic> toJson() => {
    'version': 2,
    'confirmedSteamId64': confirmedAccount?.steamId64,
    'latest': latest.values.map((s) => s.toJson()).toList(),
    'lastKnown': lastKnown.values.map((s) => s.toJson()).toList(),
    'baselines': baselines.values
        .expand((values) => values)
        .map((b) => b.toJson())
        .toList(),
  };
  factory SteamPlaytimeData.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1 && j['version'] != 2 ||
        j['version'] == 1 && j.containsKey('baselines')) {
      throw const FormatException('Unsupported Steam snapshot version');
    }
    Map<String, SteamPlaytimeSnapshot> read(String field) {
      final values = <String, SteamPlaytimeSnapshot>{};
      for (final item in j[field] as List) {
        final snapshot = SteamPlaytimeSnapshot.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (values.containsKey(snapshot.key) ||
            field == 'lastKnown' && snapshot.lifetimeMinutes == null) {
          throw const FormatException('Invalid Steam snapshot entries');
        }
        values[snapshot.key] = snapshot;
      }
      return values;
    }

    final baselines = <String, List<PlaytimeBaseline>>{};
    for (final entry
        in (j['version'] == 1 ? const [] : j['baselines'] as List)) {
      final b = PlaytimeBaseline.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );
      final history = baselines.putIfAbsent(b.key, () => []);
      if (b.revision != history.length + 1) {
        throw const FormatException('Invalid baseline revision history');
      }
      history.add(b);
    }
    return SteamPlaytimeData(
      confirmedAccount: j['confirmedSteamId64'] == null
          ? null
          : SteamPlaytimeAccount(j['confirmedSteamId64'] as String),
      latest: read('latest'),
      lastKnown: read('lastKnown'),
      baselines: baselines,
    );
  }
}

class SteamPlaytimeStore {
  SteamPlaytimeStore(Directory profileDirectory)
    : file = File(p.join(profileDirectory.path, 'steam_playtime.json'));
  final File file;
  File get _backup => File('${file.path}.bak');
  Future<void> _tail = Future.value();
  bool _closing = false;

  /// Seal synchronously, then drain mutations already admitted to the queue.
  Future<void> close() {
    _closing = true;
    return _tail;
  }

  static int _serial = 0;

  Future<SteamPlaytimeData> _decode(File source) async {
    if (await source.length() > 16 * 1024 * 1024) {
      throw const SteamPlaytimeStorageFailure();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in source.openRead(0, 16 * 1024 * 1024 + 1)) {
      bytes.add(chunk);
    }
    if (bytes.length > 16 * 1024 * 1024) {
      throw const SteamPlaytimeStorageFailure();
    }
    final j =
        jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
    // A newer version must not be downgraded by falling back to an older backup.
    if (j['version'] != 1 && j['version'] != 2) {
      throw const SteamPlaytimeStorageFailure();
    }
    return SteamPlaytimeData.fromJson(j);
  }

  Future<SteamPlaytimeData> load() async {
    var existed = false;
    for (final source in [file, _backup]) {
      try {
        final value = await _decode(source);
        return source.path == file.path
            ? value
            : SteamPlaytimeData(
                confirmedAccount: value.confirmedAccount,
                latest: value.latest,
                lastKnown: value.lastKnown,
                baselines: value.baselines,
                recoveredFromBackup: true,
              );
      } on FileSystemException catch (e) {
        final missingCodes = Platform.isWindows ? [2, 3] : [2];
        if (!missingCodes.contains(e.osError?.errorCode)) {
          throw const SteamPlaytimeStorageFailure();
        }
      } on SteamPlaytimeStorageFailure {
        rethrow;
      } catch (_) {
        existed = true;
      }
    }
    if (existed) throw const SteamPlaytimeStorageFailure();
    return SteamPlaytimeData();
  }

  /// Lock and reload inside the serialized mutation, preventing lost refreshes
  /// between store instances. A failed lock/save leaves the old association intact.
  Future<T> update<T>(
    Future<(SteamPlaytimeData, T)> Function(SteamPlaytimeData) change,
  ) {
    if (_closing) {
      return Future<T>.error(const SteamPlaytimeStorageFailure());
    }
    final task = _tail.then((_) async {
      RandomAccessFile? lock;
      var locked = false;
      try {
        await file.parent.create(recursive: true);
        lock = await File('${file.path}.lock').open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        locked = true;
        final current = await load();
        // Backup recovery may omit the last accepted baseline revision. Expose
        // it read-only, never silently normalize it into a newer primary.
        if (current.recoveredFromBackup) {
          throw const SteamPlaytimeStorageFailure();
        }
        final (next, result) = await change(current);
        final encoded = jsonEncode(next.toJson());
        if (utf8.encode(encoded).length > 16 * 1024 * 1024) {
          throw const SteamPlaytimeStorageFailure();
        }
        // Validate a full round trip before replacing any persisted document.
        SteamPlaytimeData.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
        if (await file.exists()) {
          try {
            await _decode(file);
            await _replace(_backup, await file.readAsString());
          } on SteamPlaytimeStorageFailure {
            rethrow;
          } on FormatException {
            /* Preserve the known-good backup during recovery. */
          } on TypeError {
            /* Same for a corrupt primary with a valid backup. */
          } on ArgumentError {
            /* Invalid enum names are also corrupt schema, not a reset signal. */
          }
        }
        await _replace(file, encoded);
        return result;
      } on SteamAccountConfirmationExpired {
        rethrow;
      } on PlaytimeReconciliationFailure {
        rethrow;
      } on SteamPlaytimeStorageFailure {
        rethrow;
      } catch (_) {
        throw const SteamPlaytimeStorageFailure();
      } finally {
        if (locked) await lock?.unlock();
        await lock?.close();
      }
    });
    _tail = task.then((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> _replace(File target, String value) async {
    final pending = File('${target.path}.pending.$pid.${_serial++}');
    try {
      await pending.writeAsString(value, flush: true);
      // Dart rename replaces a file at the destination, without deleting it first.
      await pending.rename(target.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }
}
