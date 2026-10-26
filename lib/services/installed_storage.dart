import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

class InstalledStorage {
  const InstalledStorage(this.path, this.bytes, this.checkedAt, {this.message});
  final String path;
  final int? bytes;
  final DateTime checkedAt;
  final String? message;
  String get drive => p.windows.isAbsolute(path)
      ? p.windows.rootPrefix(path).replaceAll('\\', '')
      : p.rootPrefix(path);
  Map<String, dynamic> toJson() => {
    'path': path,
    'bytes': bytes,
    'checkedAt': checkedAt.toIso8601String(),
    'message': message,
  };
  factory InstalledStorage.fromJson(Map<String, dynamic> j) => InstalledStorage(
    j['path'] as String,
    j['bytes'] as int?,
    DateTime.parse(j['checkedAt'] as String),
    message: j['message'] as String?,
  );
}

String storageSize(int? bytes) {
  if (bytes == null) return 'Unavailable';
  if (bytes == 0) return '0 B';
  if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  if (bytes < 1000000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
}

/// A serial worker isolate scans logical file bytes without following links.
/// Only profile requests/explicit refreshes scan; tracking never triggers scans.
class InstalledStorageService {
  InstalledStorageService(
    this.cacheFile, {
    Future<InstalledStorage> Function(String)? measure,
    DateTime Function()? now,
  }) : measure = measure ?? _measure,
       now = now ?? DateTime.now;
  final File cacheFile;
  final Future<InstalledStorage> Function(String) measure;
  final DateTime Function() now;
  final _cache = <String, InstalledStorage>{};
  final _pending = <String, Future<InstalledStorage>>{};
  Future<void>? _load;
  Future<void> _tail = Future.value();

  Future<void> _read() async {
    try {
      final entries = jsonDecode(await cacheFile.readAsString()) as List;
      for (final e in entries) {
        final value = InstalledStorage.fromJson(Map<String, dynamic>.from(e));
        _cache[p.normalize(value.path).toLowerCase()] = value;
      }
    } catch (_) {
      /* Missing/corrupt cache is optional and can be rebuilt. */
    }
  }

  Future<InstalledStorage> inspect(String path, {bool refresh = false}) async {
    await (_load ??= _read());
    final normalized = p.normalize(path), key = p.normalize(path).toLowerCase();
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        cached.bytes != null &&
        now().difference(cached.checkedAt).inHours < 24 &&
        !now().isBefore(cached.checkedAt)) {
      return cached;
    }
    if (_pending[key] != null) return _pending[key]!;
    final task = _tail.then((_) async {
      final value = await measure(normalized);
      _cache[key] = value;
      try {
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(
          jsonEncode(_cache.values.map((v) => v.toJson()).toList()),
          flush: true,
        );
      } catch (_) {
        /* A failed cache write does not change the vault. */
      }
      return value;
    });
    _pending[key] = task;
    _tail = task.then((_) {}, onError: (Object _) {});
    try {
      return await task;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<InstalledStorage> _measure(String path) => Isolate.run(() {
    var bytes = 0, failed = false;
    final queue = <String>[path];
    if (!p.isAbsolute(path) || !Directory(path).existsSync()) {
      return InstalledStorage(
        path,
        null,
        DateTime.now(),
        message: 'Installation folder is missing or unavailable.',
      );
    }
    while (queue.isNotEmpty) {
      final dir = queue.removeLast();
      try {
        for (final entry in Directory(dir).listSync(followLinks: false)) {
          if (entry is Directory) {
            queue.add(entry.path);
          } else if (entry is File) {
            try {
              bytes += entry.lengthSync();
            } on FileSystemException {
              failed = true;
            }
          }
        }
      } on FileSystemException {
        failed = true;
      }
    }
    return InstalledStorage(
      path,
      failed ? null : bytes,
      DateTime.now(),
      message: failed
          ? 'Some files could not be read. Retry when the drive is available.'
          : 'Logical installed file size; links are excluded.',
    );
  });
}
