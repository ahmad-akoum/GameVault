// Opt-in, read-only local discovery evidence. Never launches a game or writes a
// launcher record. Keep its machine-specific output private.
import 'dart:convert';
import 'dart:io';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/epic_scanner.dart';

Future<void> main(List<String> args) async {
  final steam = await SteamScanner().scan([]);
  final epic = await EpicScanner().scan();
  final sizes = <String, int?>{};
  if (args.contains('--storage')) {
    // The audit does not write a persistent cache. Each measurement is isolated.
    for (final game in epic.games) {
      // Use an intentionally absent cache parent: no cache instance is needed
      // for discovery. Storage is tested through the app/service unit suite.
      sizes[game.identity.appName] = await Directory(game.path)
          .list(recursive: true, followLinks: false)
          .where((e) => e is File)
          .asyncMap((e) => (e as File).length())
          .fold<int>(0, (a, b) => a + b);
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'steamLibraries': steam.paths,
      'steamCount': steam.games.length,
      'steamGames': [
        for (final g in steam.games)
          {'id': g.appId, 'title': g.name, 'library': g.libraryPath},
      ],
      'steamWarnings': steam.warnings,
      'epic': [
        for (final g in epic.games)
          {
            'title': g.title,
            'appName': g.identity.appName,
            'path': g.path,
            'launchExecutable': g.launchExecutable,
            'launchUri': g.identity.launchUri,
            if (sizes.containsKey(g.identity.appName))
              'installedBytes': sizes[g.identity.appName],
          },
      ],
      'epicWarnings': epic.warnings,
      'mutations': 0,
      'gameLaunches': 0,
    }),
  );
}
