import 'package:flutter/material.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';

import 'library_pages.dart';
import 'detected_page.dart';
import 'details_page.dart';
import 'settings_page.dart';

class VaultShell extends StatefulWidget {
  const VaultShell({super.key, required this.controller});
  final VaultController controller;
  @override
  State<VaultShell> createState() => _VaultShellState();
}

class _VaultShellState extends State<VaultShell> {
  int page = 0;
  int? detail;
  GameStatus? initialStatus;
  int libraryKey = 0;
  void _navigate(int value) => setState(() {
    page = value;
    detail = null;
    initialStatus = null;
  });
  void _library([GameStatus? status]) => setState(() {
    page = 1;
    detail = null;
    initialStatus = status;
    libraryKey++;
  });
  void _open(VaultGame g) => setState(() => detail = g.appId);
  void _scan() {
    if (widget.controller.settings.paths.isEmpty) {
      _navigate(3);
      return;
    }
    _navigate(4);
    widget.controller.scan();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    if (!c.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (c.fatalError != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 45),
                const SizedBox(height: 20),
                Text(
                  'Unable to open GameVault',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text(c.fatalError!, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                SelectableText(c.store.directory.path),
              ],
            ),
          ),
        ),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 1050;
    final content = detail != null
        ? DetailsPage(
            key: ValueKey(detail),
            controller: c,
            id: detail!,
            onBack: () => setState(() => detail = null),
          )
        : switch (page) {
            0 => HomePage(
              controller: c,
              onOpen: _open,
              onScan: _scan,
              onLibrary: _library,
            ),
            1 => LibraryPage(
              key: ValueKey('library-$libraryKey'),
              controller: c,
              onOpen: _open,
              onScan: _scan,
              initialStatus: initialStatus,
            ),
            2 => LibraryPage(
              key: const ValueKey('favorites'),
              controller: c,
              onOpen: _open,
              onScan: _scan,
              favorites: true,
            ),
            3 => SettingsPage(controller: c, onScan: _scan),
            _ => DetectedPage(
              controller: c,
              onSettings: () => _navigate(3),
              onLibrary: () => _library(),
            ),
          };
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: compact ? 78 : 214,
            decoration: BoxDecoration(
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xff121417)
                  : const Color(0xffeaece7),
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 19 : 24,
                    30,
                    compact ? 19 : 20,
                    35,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        color: scheme.primary,
                        size: 27,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'GameVault',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _nav(0, Icons.home_outlined, 'Home', compact),
                _nav(1, Icons.grid_view_outlined, 'My Library', compact),
                _nav(2, Icons.favorite_border, 'Favorites', compact),
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
                  child: const Divider(),
                ),
                const SizedBox(height: 16),
                _nav(4, Icons.manage_search, 'Find games', compact),
                const Spacer(),
                _nav(3, Icons.tune, 'Settings', compact),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 0 : 24,
                    18,
                    compact ? 0 : 24,
                    22,
                  ),
                  child: Text(
                    compact ? 'V1' : 'PERSONAL LIBRARY  /  V1',
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (c.error != null)
                  Container(
                    color: scheme.errorContainer,
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.error!,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          onPressed: c.dismissError,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 24 : 36,
                      30,
                      compact ? 24 : 36,
                      24,
                    ),
                    child: content,
                  ),
                ),
                if (c.importing && page != 4)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.activity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(int value, IconData icon, String label, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final selected = page == value;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12, vertical: 3),
      child: Tooltip(
        message: compact ? label : '',
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () {
              if (value == 4 && widget.controller.detected.isEmpty) {
                _scan();
              } else {
                _navigate(value);
              }
            },
            child: Container(
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (value == 1)
                      Text(
                        '${widget.controller.games.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
