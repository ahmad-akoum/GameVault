import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'models/game.dart';
import 'services/local_store.dart';
import 'services/steam_scanner.dart';
import 'services/metadata_provider.dart';
import 'services/hltb_provider.dart';
import 'services/windows_games.dart';
import 'services/epic_scanner.dart';
import 'services/installed_storage.dart';
import 'services/windows_startup.dart';
import 'services/steam_local_playtime.dart';
import 'services/steam_playtime_service.dart';
import 'services/steam_playtime_store.dart';
import 'state/vault_controller.dart';
import 'ui/theme.dart';
import 'ui/vault_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  const options = WindowOptions(
    size: Size(1280, 840),
    minimumSize: Size(360, 620),
    center: true,
    title: 'GameVault',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Color(0xff17191d),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Portable local-first storage. Development/test artifacts remain inside the
  // new project; a shipped release keeps data next to its executable.
  const dataOverride = String.fromEnvironment('GAMEVAULT_DATA_DIR');
  final dataPath = Platform.environment['GAMEVAULT_DATA_DIR'] ?? dataOverride;
  final directory = Directory(
    dataPath.isNotEmpty
        ? dataPath
        : p.join(p.dirname(Platform.resolvedExecutable), 'vault_data'),
  );
  final store = LocalStore(directory);
  final controller = VaultController(
    store: store,
    scanner: SteamScanner(),
    metadata: SteamMetadataProvider(store.artwork),
    hltb: WebsiteHltbProvider(),
    platform: WindowsGames(),
    epicScanner: EpicScanner(),
    storageService: InstalledStorageService(
      File(p.join(store.directory.path, 'storage_cache.json')),
    ),
    startup: WindowsStartup(),
    steamPlaytime: SteamPlaytimeService(
      SteamLocalPlaytimeProvider(),
      SteamPlaytimeStore(directory),
    ),
  );
  final initialization = controller.initialize();
  runApp(GameVaultApp(controller: controller, initialization: initialization));
  await initialization;
}

class GameVaultApp extends StatefulWidget {
  const GameVaultApp({
    super.key,
    required this.controller,
    this.manageWindow = true,
    this.initialization,
  });
  final VaultController controller;
  final bool manageWindow;
  final Future<void>? initialization;
  @override
  State<GameVaultApp> createState() => _GameVaultAppState();
}

class _GameVaultAppState extends State<GameVaultApp> with WindowListener {
  static const _tray = MethodChannel('gamevault/tray');
  Future<void>? _exit;
  bool _handlingClose = false;
  String? _exitSaveError;
  @override
  void initState() {
    super.initState();
    if (widget.manageWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
      _tray.setMethodCallHandler((call) async {
        if (call.method == 'exit') await _exitGameVault();
      });
    }
  }

  @override
  void dispose() {
    if (widget.manageWindow) {
      windowManager.removeListener(this);
      _tray.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (_handlingClose || _exit != null) return;
    _handlingClose = true;
    try {
      await widget.initialization;
      if (_exit != null) return;
      if (_exitSaveError == null &&
          !widget.controller.storageBlocked &&
          widget.controller.settings.closeToTray) {
        try {
          if (await _tray.invokeMethod<bool>('hide') == true) return;
        } on PlatformException {
          // If the tray is unavailable, take the normal exit path.
        } on MissingPluginException {
          // A runner without tray support still closes safely.
        }
      }
      await _exitGameVault();
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _exitGameVault() => _exit ??= _shutdown();

  Future<void> _shutdown() async {
    await widget.initialization;
    try {
      await widget.controller.shutdown();
    } on StorageFailure catch (e) {
      if (mounted) setState(() => _exitSaveError = e.message);
      try {
        await windowManager.show();
        await windowManager.focus();
      } finally {
        _exit = null;
      }
      return;
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final settings = widget.controller.settings;
      return MaterialApp(
        title: 'GameVault',
        debugShowCheckedModeBanner: false,
        theme: vaultTheme(
          Brightness.light,
          settings.accent,
          background: settings.background,
          surface: settings.surface,
        ),
        darkTheme: vaultTheme(
          Brightness.dark,
          settings.accent,
          background: settings.background,
          surface: settings.surface,
        ),
        themeMode: switch (settings.theme) {
          AppearanceMode.dark => ThemeMode.dark,
          AppearanceMode.light => ThemeMode.light,
          AppearanceMode.system => ThemeMode.system,
        },
        home: Builder(
          builder: (context) => widget.manageWindow
              ? Column(
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: SizedBox(
                        height: 38,
                        child: Row(
                          children: [
                            Expanded(
                              child: DragToMoveArea(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'GAMEVAULT  /  YOUR PERSONAL PLAY SPACE',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      letterSpacing: 1.8,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Minimize',
                              onPressed: windowManager.minimize,
                              icon: const Icon(Icons.remove, size: 16),
                            ),
                            IconButton(
                              tooltip: 'Maximize or restore',
                              onPressed: () async {
                                if (await windowManager.isMaximized()) {
                                  await windowManager.unmaximize();
                                } else {
                                  await windowManager.maximize();
                                }
                              },
                              icon: const Icon(Icons.crop_square, size: 15),
                            ),
                            IconButton(
                              tooltip: 'Close GameVault',
                              onPressed: windowManager.close,
                              icon: const Icon(Icons.close, size: 17),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _exitSaveError == null
                          ? VaultShell(controller: widget.controller)
                          : Material(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Could not save the final session',
                                      ),
                                      Text(_exitSaveError!),
                                      const Text(
                                        'Tracking has stopped. Check available disk space and vault access, then retry saving and exiting.',
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        onPressed: _exitGameVault,
                                        child: const Text(
                                          'Retry Save and Exit',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                )
              : VaultShell(controller: widget.controller),
        ),
      );
    },
  );
}
