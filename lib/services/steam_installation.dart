import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'steam_scanner.dart';
import 'steam_updates.dart';

enum InstallationStatus {
  installed('Installed'),
  missing('Not Installed'),
  needsRefresh('Needs Refresh'),
  unknown('Unknown');

  const InstallationStatus(this.label);
  final String label;
}

class InstallationEvidence {
  const InstallationEvidence(
    this.status,
    this.message, {
    this.installPath,
    this.libraryPath,
    this.buildId,
    this.updated,
  });
  final InstallationStatus status;
  final String message;
  final String? installPath, libraryPath, buildId;
  final DateTime? updated;
}

/// Reads only configured libraries and one AppID manifest per library.
/// Never writes Steam metadata or guesses update availability from build age.
class SteamInstallation {
  SteamInstallation(this.scanner);
  final SteamScanner scanner;
  static bool validAppId(int id) => id > 0 && id <= 0xffffffff;

  /// Resolve on demand: a surviving old folder is not proof of installation.
  /// Reuse AppID/library validation rather than guessing paths or writing metadata.
  Future<String> directoryFor(VaultGame game, List<String> roots) async {
    if (game.isManual) {
      if (p.isAbsolute(game.installPath) &&
          await Directory(game.installPath).exists()) {
        return game.installPath;
      }
      final executable = game.executablePath;
      if (executable != null &&
          p.isAbsolute(executable) &&
          await File(executable).exists()) {
        return p.dirname(executable);
      }
    } else {
      final evidence = await inspect(game, roots);
      if (evidence.installPath != null) return evidence.installPath!;
    }
    throw const FileSystemException(
      'The installation directory could not be verified. Check its library drive.',
    );
  }

  Future<InstallationEvidence> inspect(
    VaultGame game,
    List<String> roots, {
    List<String>? discoveredSteamRoots,
  }) async {
    if (game.isManual) {
      return InstallationEvidence(
        await Directory(game.installPath).exists()
            ? InstallationStatus.installed
            : InstallationStatus.unknown,
        'Local game directory verification only.',
      );
    }
    if (!game.isSteam || !validAppId(game.appId)) {
      return const InstallationEvidence(
        InstallationStatus.unknown,
        'A valid Steam App ID is required.',
      );
    }
    final steamRoots =
        discoveredSteamRoots ?? await scanner.installationRoots();
    final queue = {...roots, game.libraryPath, ...steamRoots}.toList();
    final visited = <String>{};
    final found = <InstallationEvidence>[];
    final indexedApps = <int, DateTime>{};
    var inconsistent = steamRoots.isEmpty || !p.isAbsolute(game.libraryPath);
    var manifestConflict = false;
    for (var i = 0; i < queue.length; i++) {
      final root = p.normalize(queue[i]);
      if (!p.isAbsolute(root) || !visited.add(root.toLowerCase())) continue;
      try {
        final warnings = <String>[];
        final libraries = await scanner.discoverPaths(
          root,
          warnings,
          indexedApps,
        );
        if (warnings.isNotEmpty) inconsistent = true;
        for (final lib in libraries) {
          if (!visited.contains(p.normalize(lib).toLowerCase())) queue.add(lib);
        }
        final library = p.basename(root).toLowerCase() == 'steamapps'
            ? p.dirname(root)
            : root;
        final file = File(
          p.join(library, 'steamapps', 'appmanifest_${game.appId}.acf'),
        );
        String manifest;
        try {
          manifest = await file.readAsString();
        } on PathNotFoundException {
          // An absent manifest is only meaningful on a readable library.
          await file.parent.list().isEmpty;
          continue;
        } on FileSystemException {
          // A named manifest that cannot be read is different from an
          // unrelated library that cannot be reached.
          final name = p.basename(file.path).toLowerCase();
          if (await file.parent.list().any(
            (entry) => p.basename(entry.path).toLowerCase() == name,
          )) {
            manifestConflict = true;
          }
          inconsistent = true;
          continue;
        }
        Object? m;
        try {
          m = ValveKeyValues.parse(manifest)['appstate'];
        } on FormatException {
          manifestConflict = true;
          continue;
        }
        if (m is! Map || '${m['appid']}' != '${game.appId}') {
          manifestConflict = true;
          continue;
        }
        final dir = m['installdir']?.toString() ?? '';
        if (dir.isEmpty ||
            p.isAbsolute(dir) ||
            dir.contains('..') ||
            dir.contains('/') ||
            dir.contains('\\')) {
          manifestConflict = true;
          continue;
        }
        final path = p.join(library, 'steamapps', 'common', dir);
        final flags = int.tryParse('${m['stateflags']}');
        final build = int.tryParse('${m['buildid']}') ?? 0;
        if (flags == null ||
            (flags & ~0x1ffff) != 0 ||
            (flags & 4) == 0 ||
            (flags & (1 | 32 | 128 | 2048 | 4096 | 32768)) != 0 ||
            ((flags & (256 | 512 | 1024)) != 0 && build <= 0)) {
          manifestConflict = true;
          continue;
        }
        if (!await Directory(path).exists()) {
          manifestConflict = true;
          continue;
        }
        if (found.any(
          (e) => p.equals(e.installPath!.toLowerCase(), path.toLowerCase()),
        )) {
          continue;
        }
        final seconds = int.tryParse('${m['lastupdated']}');
        found.add(
          InstallationEvidence(
            p.equals(
                  path.toLowerCase(),
                  p.normalize(game.installPath).toLowerCase(),
                )
                ? InstallationStatus.installed
                : InstallationStatus.needsRefresh,
            'Installation verified against its Steam AppID manifest.',
            installPath: path,
            libraryPath: library,
            buildId: m['buildid']?.toString(),
            updated: seconds != null && seconds > 0 && seconds < 4102444800
                ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
                : null,
          ),
        );
      } on FileSystemException {
        inconsistent = true;
      } on FormatException {
        inconsistent = true;
      }
    }
    if (manifestConflict) {
      return const InstallationEvidence(
        InstallationStatus.unknown,
        'Steam records for this App ID are incomplete or contradictory.',
      );
    }
    if (found.length == 1) return found.single;
    if (found.length > 1) {
      return const InstallationEvidence(
        InstallationStatus.unknown,
        'Multiple installations were found. Resolve the duplicate in Steam before refreshing.',
      );
    }
    final indexedAt = indexedApps[game.appId];
    if (!inconsistent && indexedAt != null) {
      inconsistent = !await SteamUpdateService(
        scanner,
      ).confirmsUninstallAfter(game.appId, steamRoots, indexedAt);
    }
    return InstallationEvidence(
      inconsistent ? InstallationStatus.unknown : InstallationStatus.missing,
      inconsistent
          ? 'Steam metadata is incomplete or inaccessible. No paths were changed.'
          : 'Steam has no installation record for this game in the checked libraries.',
    );
  }
}
