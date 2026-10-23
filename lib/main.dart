import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'models/game.dart';
import 'services/local_store.dart';
import 'services/steam_scanner.dart';
import 'services/metadata_provider.dart';
import 'services/hltb_provider.dart';
import 'services/windows_games.dart';
import 'state/vault_controller.dart';
import 'ui/theme.dart';
import 'ui/vault_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
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
  );
  runApp(GameVaultApp(controller: controller));
  await controller.initialize();
}

class GameVaultApp extends StatefulWidget {
  const GameVaultApp({
    super.key,
    required this.controller,
    this.manageWindow = true,
  });
  final VaultController controller;
  final bool manageWindow;
  @override
  State<GameVaultApp> createState() => _GameVaultAppState();
}

class _GameVaultAppState extends State<GameVaultApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (widget.manageWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  @override
  void dispose() {
    if (widget.manageWindow) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    // Pending saves finish before releasing the data lock; enrichment can be
    // retried later and never blocks closing the window.
    await widget.controller.shutdown();
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
                    Expanded(child: VaultShell(controller: widget.controller)),
                  ],
                )
              : VaultShell(controller: widget.controller),
        ),
      );
    },
  );
}
