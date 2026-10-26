import 'package:flutter/material.dart';

import '../state/vault_controller.dart';
import 'components.dart';
import 'responsive.dart';

class DetectedPage extends StatefulWidget {
  const DetectedPage({
    super.key,
    required this.controller,
    required this.onSettings,
    required this.onLibrary,
  });
  final VaultController controller;
  final VoidCallback onSettings, onLibrary;
  @override
  State<DetectedPage> createState() => _DetectedPageState();
}

class _DetectedPageState extends State<DetectedPage> {
  final selected = <int>{};
  String search = '';
  bool unimportedOnly = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    selected.removeWhere((id) => c.game(id) != null);
    final games = c.detected
        .where(
          (g) =>
              g.name.toLowerCase().contains(search.toLowerCase()) &&
              (!unimportedOnly || c.game(g.appId) == null),
        )
        .toList();
    return ResponsivePage(
      children: [
        PageHeading(
          'Find your games',
          'Installed in Steam or Epic Games. Choose what belongs in your vault.',
          action: OutlinedButton.icon(
            onPressed: c.scanning ? null : () => c.scan(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Scan again'),
          ),
        ),
        if (c.scanning) const LinearProgressIndicator(minHeight: 2),
        AdaptiveRow(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: const InputDecoration(
                  hintText: 'Search detected games',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => setState(
                () => selected.addAll(
                  games
                      .where((g) => c.game(g.appId) == null)
                      .map((g) => g.appId),
                ),
              ),
              child: const Text('Select visible'),
            ),
            TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => setState(selected.clear),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Not added'),
              selected: unimportedOnly,
              onSelected: (v) => setState(() => unimportedOnly = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveRow(
          children: [
            Text(
              '${c.detected.length} detected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 16),
            Text(
              '${c.detected.where((g) => c.game(g.appId) != null).length} already in GameVault',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: widget.onSettings,
              child: const Text('Manage folders'),
            ),
          ],
        ),
        if (c.scannedPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Scanned ${c.scannedPaths.length} Steam libraries: ${c.scannedPaths.join(' • ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (c.scanWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline, size: 19),
              title: Text(
                '${c.scanWarnings.length} scan ${c.scanWarnings.length == 1 ? 'notice' : 'notices'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: c.scanWarnings
                  .map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          w,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        Expanded(
          child: c.scanning
              ? const Center(child: CircularProgressIndicator())
              : games.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_open, size: 42),
                      const SizedBox(height: 16),
                      Text(
                        c.detected.isEmpty
                            ? 'No installed games found'
                            : 'No games match this search',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('Check your folders and scan again.'),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: widget.onSettings,
                        child: const Text('Manage Steam folders'),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => ListView.separated(
                    shrinkWrap: !constraints.hasBoundedHeight,
                    physics: !constraints.hasBoundedHeight
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: games.length,
                    separatorBuilder: (_, i) => const Divider(),
                    itemBuilder: (context, i) {
                      final g = games[i];
                      final imported = c.game(g.appId) != null;
                      final checked = selected.contains(g.appId);
                      return Material(
                        color: checked
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.07)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: imported || c.importing
                              ? null
                              : () => setState(
                                  () => checked
                                      ? selected.remove(g.appId)
                                      : selected.add(g.appId),
                                ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 8,
                            ),
                            child: AdaptiveRow(
                              children: [
                                Checkbox(
                                  value: imported || checked,
                                  onChanged: imported || c.importing
                                      ? null
                                      : (v) => setState(
                                          () => v!
                                              ? selected.add(g.appId)
                                              : selected.remove(g.appId),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 48,
                                  height: 70,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: GameArtwork(
                                      url: g.coverUrl,
                                      title: g.name,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        g.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${g.sourceLabel} • ${g.libraryPath}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    imported
                                        ? 'In your vault'
                                        : checked
                                        ? 'Selected'
                                        : 'Not added',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: imported || checked
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AdaptiveRow(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.importing ? c.activity : '${selected.length} selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.importing
                          ? 'Games are saved first; online information is fetched in the background.'
                          : 'Only selected games are added. Launcher and game files stay untouched.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (c.importing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: widget.onLibrary,
                child: const Text('View library'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: c.importing || selected.isEmpty
                    ? null
                    : () {
                        c.importGames({...selected});
                      },
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  'Add ${selected.isEmpty ? 'selected' : selected.length} ${selected.length == 1 ? 'game' : 'games'}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
