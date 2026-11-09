import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import 'session_tracker.dart';
import 'steam_installation.dart';

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
  static Future<DateTime?> steamStarted() async {
    final result = await channel.invokeMethod<int>(
      'steamStarted',
      <String, Object>{},
    );
    return result == null ? null : DateTime.fromMillisecondsSinceEpoch(result);
  }

  @override
  Future<void> launch(VaultGame game) async {
    if (game.isEpic) {
      if (game.epic?.valid != true ||
          !await Directory(game.installPath).exists()) {
        throw const FileSystemException(
          'Epic installation or launcher identity is unavailable.',
        );
      }
      await channel.invokeMethod<void>('openEpic', {
        'namespace': game.epic!.namespace,
        'catalogId': game.epic!.catalogId,
        'appName': game.epic!.appName,
      });
      return;
    }
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
    }
    await channel.invokeMethod<void>('launch', {
      'steamId': game.isManual ? 0 : game.appId,
      'executable': game.isManual ? game.executablePath : '',
    });
  }

  @override
  Future<WindowsSample> sample(
    List<VaultGame> games, {
    bool includeBackground = false,
  }) async {
    final result = await channel.invokeMapMethod<String, dynamic>('sample', {
      if (includeBackground) 'includeBackground': true,
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

  static Future<void> openLocation(String path, {bool select = false}) async {
    if (!p.isAbsolute(path) ||
        !(select
            ? await File(path).exists()
            : await Directory(path).exists())) {
      throw const FileSystemException(
        'The location is missing or unavailable.',
      );
    }
    await channel.invokeMethod<void>('openLocation', {
      'path': path,
      'select': select,
    });
  }

  static Future<void> openSteam(int appId) async {
    if (appId <= 0) return;
    await channel.invokeMethod<void>('openSteam', {'steamId': appId});
  }

  static Future<void> requestSteamInstallation(
    int appId, {
    required bool uninstall,
  }) async {
    if (!SteamInstallation.validAppId(appId)) {
      throw ArgumentError.value(appId, 'appId', 'Invalid Steam App ID');
    }
    await channel.invokeMethod<void>(
      uninstall ? 'uninstallSteam' : 'installSteam',
      {'steamId': appId},
    );
  }

  static Future<void> openEpicLibrary() =>
      channel.invokeMethod<void>('openEpicLibrary', <String, Object>{});

  static Future<void> openWeb(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    await channel.invokeMethod<void>('openWeb', {'url': url});
  }
}
