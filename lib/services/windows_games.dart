import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'session_tracker.dart';

class WindowsSample {
  WindowsSample(this.games, this.idleSeconds);
  final List<GameObservation> games;
  final int idleSeconds;
}

abstract class GamePlatform {
  Future<void> launch(VaultGame game);
  Future<WindowsSample> sample(List<VaultGame> games);
}

class WindowsGames implements GamePlatform {
  static const channel = MethodChannel('gamevault/windows');
  @override
  Future<void> launch(VaultGame game) async {
    if (game.isManual) {
      final path = game.executablePath;
      if (path == null ||
          !p.isAbsolute(path) ||
          !path.toLowerCase().endsWith('.exe') ||
          !await File(path).exists()) {
        throw const FileSystemException(
          'The selected executable is missing. Choose its new location.',
        );
      }
    } else if (!await Directory(game.installPath).exists()) {
      throw const FileSystemException(
        'The game installation is missing or its drive is disconnected.',
      );
    }
    await channel.invokeMethod<void>('launch', {
      'steamId': game.isManual ? 0 : game.appId,
      'executable': game.isManual ? game.executablePath : '',
    });
  }

  @override
  Future<WindowsSample> sample(List<VaultGame> games) async {
    final result = await channel.invokeMapMethod<String, dynamic>('sample', {
      'games': games
          .map(
            (g) => {
              'id': g.appId,
              'root': g.installPath,
              'executable': g.executablePath ?? '',
            },
          )
          .toList(),
    });
    if (result == null) throw PlatformException(code: 'monitor_unavailable');
    final observations = <GameObservation>[];
    for (final item in result['games'] as List) {
      final id = item['id'] as int;
      final game = games.where((g) => g.appId == id).firstOrNull;
      if (game != null) {
        observations.add(
          GameObservation(
            id,
            game.title,
            Set<String>.from(item['processes']),
            item['focused'] == true,
          ),
        );
      }
    }
    return WindowsSample(observations, result['idleSeconds'] as int);
  }

  static Future<void> openWeb(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    await channel.invokeMethod<void>('openWeb', {'url': url});
  }
}
