// Read-only developer probe. Output belongs in ignored release_artifacts.
import 'dart:convert';
import 'dart:io';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'package:gamevault/services/steam_updates.dart';

Future<void> main() async {
  final scanner = SteamScanner();
  final roots = await scanner.installationRoots();
  final scanned = await scanner.scan(roots);
  final games = scanned.games.map(VaultGame.fromSteam).toList();
  final session = await Process.run('powershell.exe', [
    '-NoProfile',
    '-Command',
    r"$p=Get-Process steam -ErrorAction SilentlyContinue | Select-Object -First 1; if($p){$p.StartTime.ToUniversalTime().ToString('o')}",
  ]);
  final started = DateTime.tryParse(session.stdout.toString().trim());
  final states = await SteamUpdateService(
    scanner,
    steamStarted: () => Future.value(started),
  ).refresh(games, roots);
  stdout.writeln(
    jsonEncode({
      'steamRunning': started != null,
      'results': [
        for (final game in games)
          {
            'appId': game.appId,
            'title': game.title,
            'status': states[game.appId]!.summary,
            'badge': states[game.appId]!.badge,
            'source': states[game.appId]!.source,
          },
      ],
    }),
  );
}
