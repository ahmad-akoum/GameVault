import 'package:flutter/material.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';

import 'library_pages.dart';
import 'detected_page.dart';
import 'details_page.dart';
import 'settings_page.dart';
import 'activity_pages.dart';
import 'collections_page.dart';

class VaultShell extends StatefulWidget {
  const VaultShell({super.key, required this.controller});
  final VaultController controller;
  @override
  State<VaultShell> createState() => _VaultShellState();
}

class _VaultShellState extends State<VaultShell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
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
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final canToggleSidebar = MediaQuery.sizeOf(context).width >= 1050;
    final compact =
        !narrow && (!canToggleSidebar || c.settings.sidebarCollapsed);
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
            5 => StatisticsPage(controller: c, onOpen: _open),
            6 => CollectionsPage(controller: c, onOpen: _open),
            3 => SettingsPage(controller: c, onScan: _scan),
            _ => DetectedPage(
              controller: c,
              onSettings: () => _navigate(3),
              onLibrary: () => _library(),
            ),
          };
    final navigation = Container(
      width: compact ? 78 : 214,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: Column(
                      children: [
                        if (compact)
                          Icon(
                            Icons.inventory_2_outlined,
                            color: scheme.primary,
                            size: 27,
                          ),
                        Row(
                          children: [
                            if (!compact) ...[
                              Icon(
                                Icons.inventory_2_outlined,
                                color: scheme.primary,
                                size: 27,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'GameVault',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (canToggleSidebar)
                              IconButton(
                                key: const ValueKey('sidebarToggle'),
                                tooltip: compact
                                    ? 'Expand navigation'
                                    : 'Collapse navigation',
                                onPressed: () => c.setSettings(
                                  c.settings.copy(
                                    sidebarCollapsed:
                                        !c.settings.sidebarCollapsed,
                                  ),
                                ),
                                icon: Icon(
                                  compact
                                      ? Icons.chevron_right
                                      : Icons.chevron_left,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _nav(0, Icons.home_outlined, 'Home', compact),
                  _nav(1, Icons.grid_view_outlined, 'My Library', compact),
                  _nav(2, Icons.favorite_border, 'Favorites', compact),
                  _nav(6, Icons.folder_outlined, 'Collections', compact),
                  _nav(5, Icons.bar_chart_rounded, 'Activity', compact),
                  const SizedBox(height: 24),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 14 : 22,
                    ),
                    child: const Divider(),
                  ),
                  const SizedBox(height: 16),
                  _nav(4, Icons.manage_search, 'Find games', compact),
                  _nav(7, Icons.add_box_outlined, 'Add local game', compact),
                  const Spacer(),
                  _nav(3, Icons.tune, 'Settings', compact),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      key: scaffoldKey,
      drawer: narrow ? Drawer(child: navigation) : null,
      body: Row(
        children: [
          if (!narrow) navigation,
          Expanded(
            child: Column(
              children: [
                if (narrow)
                  Builder(
                    builder: (context) => Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Open navigation',
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                  ),
                if (c.trackingError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: scheme.secondaryContainer,
                    child: Text(c.trackingError!),
                  ),
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
                      narrow
                          ? 12
                          : compact
                          ? 24
                          : 36,
                      narrow ? 8 : 30,
                      narrow
                          ? 12
                          : compact
                          ? 24
                          : 36,
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
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              scaffoldKey.currentState?.closeDrawer();
              if (value == 7) {
                importExecutable(context, widget.controller);
              } else if (value == 4 && widget.controller.detected.isEmpty) {
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
