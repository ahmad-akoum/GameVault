import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'steam_installation.dart';

class EpicInstallation {
  const EpicInstallation(
    this.identity,
    this.title,
    this.path,
    this.launchExecutable,
  );
  final EpicIdentity identity;
  final String title, path, launchExecutable;
}

class EpicScanResult {
  const EpicScanResult(this.games, this.warnings);
  final List<EpicInstallation> games;
  final List<String> warnings;
}

/// Reads only the launcher's local .item installation records, never account
/// credentials, game contents, download state, or a whole-drive search.
class EpicScanner {
  EpicScanner({Directory? manifests})
    : manifests =
          manifests ??
          Directory(
            p.join(
              Platform.environment['ProgramData'] ?? r'C:\ProgramData',
              'Epic',
              'EpicGamesLauncher',
              'Data',
              'Manifests',
            ),
          );
  final Directory manifests;

  Future<EpicScanResult> scan() async {
    final games = <String, EpicInstallation>{};
    final ambiguous = <String>{};
    final warnings = <String>[];
    if (!await manifests.exists()) return const EpicScanResult([], []);
    try {
      await for (final entity in manifests.list(followLinks: false)) {
        if (entity is! File ||
            p.extension(entity.path).toLowerCase() != '.item') {
          continue;
        }
        try {
          if (await entity.length() > 2 * 1024 * 1024) {
            throw const FormatException();
          }
          final j =
              jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          if (j['bIsIncompleteInstall'] == true ||
              j['bIsApplication'] != true) {
            continue;
          }
          final identity = EpicIdentity(
            j['CatalogNamespace'] as String,
            j['CatalogItemId'] as String,
            j['AppName'] as String,
          );
          final title = (j['DisplayName'] as String).trim();
          final root = p.normalize(j['InstallLocation'] as String);
          final relative = (j['LaunchExecutable'] as String)
              .replaceAll('\\', p.separator)
              .replaceAll('/', p.separator);
          final executable = p.normalize(p.join(root, relative));
          if (!identity.valid ||
              title.isEmpty ||
              !p.isAbsolute(root) ||
              p.isAbsolute(relative) ||
              !p.isWithin(root, executable) ||
              p.extension(executable).toLowerCase() != '.exe') {
            throw const FormatException();
          }
          if (!await Directory(root).exists() ||
              !await File(executable).exists()) {
            warnings.add(
              '$title — Epic installation is unavailable or incomplete.',
            );
            continue;
          }
          final previous = games[identity.key];
          if (previous != null &&
              !p.equals(previous.path.toLowerCase(), root.toLowerCase())) {
            ambiguous.add(identity.key);
            warnings.add(
              '$title — multiple Epic installations; resolve in the launcher.',
            );
          }
          games[identity.key] = EpicInstallation(
            identity,
            title,
            root,
            executable,
          );
        } catch (_) {
          warnings.add(
            '${p.basename(entity.path)} — Epic installation record could not be validated.',
          );
        }
      }
    } on FileSystemException {
      warnings.add('Epic installation records are inaccessible.');
    }
    games.removeWhere((key, _) => ambiguous.contains(key));
    return EpicScanResult(
      games.values.toList()..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      ),
      warnings,
    );
  }

  Future<InstallationEvidence> inspect(VaultGame game) async {
    final matches = (await scan()).games.where(
      (g) => g.identity.key == game.epic?.key,
    );
    if (matches.length != 1) {
      return const InstallationEvidence(
        InstallationStatus.unknown,
        'No unambiguous, complete Epic installation record is available. Check the launcher and drive.',
      );
    }
    final found = matches.single;
    return InstallationEvidence(
      p.equals(found.path.toLowerCase(), game.installPath.toLowerCase())
          ? InstallationStatus.installed
          : InstallationStatus.needsRefresh,
      'Installation verified against Epic’s local manifest. Update availability is not inferred.',
      installPath: found.path,
      libraryPath: p.dirname(found.path),
    );
  }
}
