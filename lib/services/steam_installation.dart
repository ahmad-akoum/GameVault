import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'steam_scanner.dart';

enum InstallationStatus {
  installed('Installed'),
  missing('Missing'),
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
    List<String> roots,
  ) async {
    if (game.isManual) {
      return InstallationEvidence(
        await Directory(game.installPath).exists()
            ? InstallationStatus.installed
            : InstallationStatus.unknown,
        'Local game directory verification only.',
      );
    }
    final queue = {
      ...roots,
      game.libraryPath,
      ...await scanner.installationRoots(),
    }.toList();
    final visited = <String>{};
    final found = <InstallationEvidence>[];
    var inconsistent = false;
    for (var i = 0; i < queue.length; i++) {
      final root = p.normalize(queue[i]);
      if (root.isEmpty || !visited.add(root.toLowerCase())) continue;
      try {
        final libraries = await scanner.discoverPaths(root);
        for (final lib in libraries) {
          if (!visited.contains(p.normalize(lib).toLowerCase())) queue.add(lib);
        }
        final library = p.basename(root).toLowerCase() == 'steamapps'
            ? p.dirname(root)
            : root;
        final file = File(
          p.join(library, 'steamapps', 'appmanifest_${game.appId}.acf'),
        );
        if (!await file.exists()) continue;
        final m = ValveKeyValues.parse(await file.readAsString())['appstate'];
        if (m is! Map || '${m['appid']}' != '${game.appId}') {
          inconsistent = true;
          continue;
        }
        final dir = m['installdir']?.toString() ?? '';
        if (dir.isEmpty ||
            p.isAbsolute(dir) ||
            dir.contains('..') ||
            dir.contains('/') ||
            dir.contains('\\')) {
          inconsistent = true;
          continue;
        }
        final path = p.join(library, 'steamapps', 'common', dir);
        final flags = int.tryParse('${m['stateflags']}');
        if (flags == null || (flags & 4) == 0) {
          inconsistent = true;
          continue;
        }
        if (!await Directory(path).exists()) {
          inconsistent = true;
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
    if (found.length == 1) return found.single;
    if (found.length > 1) {
      return const InstallationEvidence(
        InstallationStatus.unknown,
        'Multiple installations were found. Resolve the duplicate in Steam before refreshing.',
      );
    }
    final missing =
        !await Directory(game.installPath).exists() &&
        await Directory(p.join(game.libraryPath, 'steamapps')).exists();
    return InstallationEvidence(
      missing && !inconsistent
          ? InstallationStatus.missing
          : InstallationStatus.unknown,
      inconsistent
          ? 'Steam metadata is incomplete or inaccessible. No paths were changed.'
          : 'No verified manifest was found. A missing manifest alone does not prove the game is uninstalled.',
    );
  }
}
