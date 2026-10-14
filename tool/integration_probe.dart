import 'dart:io';
import 'package:gamevault/services/hltb_provider.dart';
import 'package:gamevault/services/steam_scanner.dart';

Future<void> main() async {
  final hltb = WebsiteHltbProvider();
  for (final title in [
    'Elden Ring',
    'Portal 2',
    'Red Dead Redemption 2',
    'Final Fantasy',
    'gamevault no such game qzxv9893',
  ]) {
    try {
      final results = await hltb.search(title);
      stdout.writeln('$title: ${results.length} result(s)');
      for (final entry in results.take(3)) {
        stdout.writeln(
          '  ${entry.title}: ${entry.main.toStringAsFixed(1)} / ${entry.extras.toStringAsFixed(1)} / ${entry.complete.toStringAsFixed(1)} hours',
        );
      }
    } on HltbFailure catch (e) {
      stdout.writeln('$title: ${e.message}');
    }
  }
  final scan = await SteamScanner().scan([r'C:\Program Files (x86)\Steam']);
  stdout.writeln(
    'Real Steam scan: ${scan.games.length} installed apps in ${scan.paths.length} libraries, ${scan.warnings.length} warnings',
  );
  for (final game in scan.games) {
    stdout.writeln('${game.appId}: ${game.name}');
  }
  hltb.client.close();
}
