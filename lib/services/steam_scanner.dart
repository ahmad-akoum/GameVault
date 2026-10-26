import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'steam_app_info.dart';

/// Valve's text KeyValues format, including nested blocks, comments and escapes.
class ValveKeyValues {
  static Map<String, dynamic> parse(String text) {
    final tokens = <String>[];
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (RegExp(r'\s').hasMatch(c) || c == '\ufeff') {
        i++;
        continue;
      }
      if (c == '/' && i + 1 < text.length && text[i + 1] == '/') {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '{' || c == '}') {
        tokens.add(c);
        i++;
        continue;
      }
      if (c == '"') {
        i++;
        final b = StringBuffer();
        var closed = false;
        while (i < text.length) {
          final x = text[i++];
          if (x == '"') {
            closed = true;
            break;
          }
          if (x == '\\' && i < text.length) {
            final next = text[i];
            if (next == '\\' || next == '"') {
              b.write(next);
              i++;
            } else {
              b.write(x);
            }
          } else {
            b.write(x);
          }
        }
        if (!closed) {
          throw const FormatException('Unterminated quoted value');
        }
        tokens.add(b.toString());
        continue;
      }
      final start = i;
      while (i < text.length && !RegExp(r'[\s{}]').hasMatch(text[i])) {
        i++;
      }
      tokens.add(text.substring(start, i));
    }
    var cursor = 0;
    Map<String, dynamic> block(bool nested, int depth) {
      if (depth > 32) {
        throw const FormatException('Excessive nesting');
      }
      final result = <String, dynamic>{};
      while (cursor < tokens.length) {
        final key = tokens[cursor++];
        if (key == '}') {
          if (!nested) {
            throw const FormatException('Unexpected closing brace');
          }
          return result;
        }
        if (key == '{' || cursor >= tokens.length) {
          throw const FormatException('Missing value');
        }
        final value = tokens[cursor++];
        if (value == '}') {
          throw const FormatException('Missing value');
        }
        result[key.toLowerCase()] = value == '{'
            ? block(true, depth + 1)
            : value;
      }
      if (nested) {
        throw const FormatException('Unclosed block');
      }
      return result;
    }

    return block(false, 0);
  }
}

class ScanFailure implements Exception {
  const ScanFailure(this.message);
  final String message;
}

class ScanResult {
  const ScanResult(this.games, this.warnings, this.paths);
  final List<SteamGame> games;
  final List<String> warnings, paths;
}

class SteamScanner {
  SteamScanner({Future<List<String>> Function()? installationRoots})
    : installationRoots = installationRoots ?? locateSteam;
  final Future<List<String>> Function() installationRoots;

  static Future<List<String>> locateSteam() async {
    if (!Platform.isWindows) return [];
    final roots = <String>[];
    for (final query in [
      ['HKCU\\Software\\Valve\\Steam', 'SteamPath'],
      ['HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam', 'InstallPath'],
      ['HKLM\\SOFTWARE\\Valve\\Steam', 'InstallPath'],
    ]) {
      try {
        final result = await Process.run('reg.exe', [
          'query',
          query[0],
          '/v',
          query[1],
        ]);
        if (result.exitCode == 0) {
          final match = RegExp(
            r'REG_SZ\s+([^\r\n]+)',
          ).firstMatch(result.stdout.toString());
          if (match != null) roots.add(match.group(1)!.trim());
        }
      } on ProcessException {
        /* Standard installation paths remain available. */
      }
    }
    for (final variable in ['ProgramFiles(x86)', 'ProgramFiles']) {
      final base = Platform.environment[variable];
      if (base != null) {
        final root = p.join(base, 'Steam');
        if (await Directory(p.join(root, 'steamapps')).exists()) {
          roots.add(root);
        }
      }
    }
    return roots;
  }

  Future<List<String>> discoverPaths(
    String root, [
    List<String>? warnings,
  ]) async {
    final normalized = p.normalize(root);
    final library = p.basename(normalized).toLowerCase() == 'steamapps'
        ? p.dirname(normalized)
        : normalized;
    final paths = <String>[library];
    for (final config in [
      p.join(library, 'steamapps', 'libraryfolders.vdf'),
      p.join(library, 'config', 'libraryfolders.vdf'),
    ]) {
      try {
        final file = File(config);
        if (!await file.exists()) {
          continue;
        }
        final value = ValveKeyValues.parse(
          await file.readAsString(),
        )['libraryfolders'];
        if (value is Map) {
          for (final entry in value.values) {
            final path = entry is Map ? entry['path'] : entry;
            if (path is String &&
                p.isAbsolute(path) &&
                !paths.any(
                  (e) => p.equals(e.toLowerCase(), path.toLowerCase()),
                )) {
              paths.add(p.normalize(path));
            }
          }
        }
      } catch (e) {
        stderr.writeln('Library config could not be read: $e');
        warnings?.add('$config — could not read Steam library configuration.');
      }
    }
    return paths;
  }

  Future<ScanResult> scan(List<String> roots) async {
    final paths = <String>[];
    final warnings = <String>[];
    final games = <int, SteamGame>{};
    final installations = await installationRoots();
    final queue = [...roots, ...installations];
    final visited = <String>{};
    for (var i = 0; i < queue.length; i++) {
      final root = p.normalize(queue[i]);
      if (!visited.add(root.toLowerCase())) continue;
      final discovered = await discoverPaths(root, warnings);
      for (final path in discovered) {
        if (!paths.any(
          (item) => p.equals(item.toLowerCase(), path.toLowerCase()),
        )) {
          paths.add(path);
        }
        if (!visited.contains(path.toLowerCase())) queue.add(path);
      }
    }
    final types = <int, String>{};
    for (final root in {...installations, ...paths}) {
      final file = File(p.join(root, 'appcache', 'appinfo.vdf'));
      if (!await file.exists()) continue;
      try {
        types.addAll(SteamAppInfo.types(await file.readAsBytes()));
      } catch (e) {
        warnings.add(
          '$root — Steam app types could not be read; unclassified entries are retained.',
        );
      }
    }
    var unclassified = 0;
    var valid = 0;
    for (final root in paths) {
      final apps = Directory(p.join(root, 'steamapps'));
      if (!await apps.exists()) {
        warnings.add('$root — no steamapps folder found.');
        continue;
      }
      valid++;
      try {
        await for (final entity in apps.list(followLinks: false)) {
          if (entity is! File ||
              !RegExp(
                r'^appmanifest_\d+\.acf$',
                caseSensitive: false,
              ).hasMatch(p.basename(entity.path))) {
            continue;
          }
          try {
            final manifest = ValveKeyValues.parse(
              await entity.readAsString(),
            )['appstate'];
            if (manifest is! Map) {
              throw const FormatException('Missing AppState');
            }
            final id = int.tryParse(manifest['appid']?.toString() ?? '');
            final name = manifest['name']?.toString().trim() ?? '';
            final install = manifest['installdir']?.toString() ?? '';
            final flags =
                int.tryParse(manifest['stateflags']?.toString() ?? '') ?? 0;
            if (id == null ||
                id <= 0 ||
                name.isEmpty ||
                install.isEmpty ||
                p.isAbsolute(install) ||
                install.contains('..') ||
                install.contains('/') ||
                install.contains('\\') ||
                p.basename(entity.path).toLowerCase() !=
                    'appmanifest_$id.acf') {
              throw const FormatException(
                'Invalid app identity or installation directory',
              );
            }
            final installPath = p.join(root, 'steamapps', 'common', install);
            // Types come from Steam's local catalog, never name/size guesses.
            final type = types[id];
            if (id == 228980 ||
                id == 480 ||
                [
                  'application',
                  'tool',
                  'music',
                  'dlc',
                  'video',
                  'config',
                  'advertising',
                  'hardware',
                ].contains(type)) {
              continue;
            }
            if ((flags & 4) == 0 || !await Directory(installPath).exists()) {
              warnings.add(
                '$name — installation is incomplete or its folder is missing.',
              );
              continue;
            }
            if (type == null) unclassified++;
            games.putIfAbsent(
              id,
              () => SteamGame(
                appId: id,
                name: name,
                installPath: installPath,
                libraryPath: root,
              ),
            );
          } catch (e) {
            stderr.writeln('Manifest ${entity.path}: $e');
            warnings.add(
              '${p.basename(entity.path)} — could not read this Steam manifest.',
            );
          }
        }
      } catch (e) {
        warnings.add('$root — could not access this library.');
        stderr.writeln(e);
      }
    }
    if (valid == 0) {
      throw const ScanFailure(
        'No valid Steam library found. Choose the Steam folder or a library folder containing steamapps.',
      );
    }
    final sorted = games.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (unclassified > 0) {
      warnings.add(
        '$unclassified installed entries have no cached Steam app type; review before importing.',
      );
    }
    return ScanResult(sorted, warnings, paths);
  }
}
