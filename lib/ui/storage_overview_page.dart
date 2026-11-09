import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import '../services/installed_storage.dart';
import '../state/vault_controller.dart';
import 'components.dart';

String storagePathKey(String path) => p.windows.normalize(path).toLowerCase();

/// A measured parent already accounts for any measured descendants.
int trackedStorageBytes(Iterable<InstalledStorage> values) {
  final measured = <String, int>{};
  for (final value in values) {
    if (value.bytes case final bytes?) {
      final key = storagePathKey(value.path);
      final existing = measured[key];
      if (existing == null || bytes > existing) measured[key] = bytes;
    }
  }
  final paths = measured.keys.toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  final roots = <String>[];
  var bytes = 0;
  for (final path in paths) {
    if (roots.any((root) => p.windows.isWithin(root, path))) continue;
    roots.add(path);
    bytes += measured[path]!;
  }
  return bytes;
}

class StorageOverviewPage extends StatefulWidget {
  const StorageOverviewPage({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final VaultController controller;
  final ValueChanged<VaultGame> onOpen;

  @override
  State<StorageOverviewPage> createState() => _StorageOverviewPageState();
}

class _StorageOverviewPageState extends State<StorageOverviewPage> {
  final results = <int, InstalledStorage>{};
  bool busy = false, cancel = false, largest = true;
  int completed = 0, count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load(refresh: false);
    });
  }

  Future<void> load({required bool refresh}) async {
    if (busy) return;
    final c = widget.controller;
    final games = List.of(c.games);
    setState(() {
      busy = true;
      cancel = false;
      completed = 0;
      count = games.length;
    });
    // Resolve installations first. Shared paths are measured only once per refresh.
    final seen = <String, InstalledStorage>{};
    try {
      for (final game in games) {
        if (!mounted || cancel) break;
        final cached = await c.overviewStorage(game, refresh: false);
        if (!mounted || cancel) break;
        final key = storagePathKey(cached.path);
        final result = refresh && cached.path.isNotEmpty
            ? seen[key] ??= await c.overviewStorage(game, refresh: true)
            : cached;
        if (!mounted) break;
        setState(() {
          results[game.appId] = result;
          completed++;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final groups = <String, List<VaultGame>>{};
    final measured = <InstalledStorage>[];
    var stale = 0, unavailable = 0;
    for (final game in c.games) {
      final value = results[game.appId];
      (groups[value == null || value.path.isEmpty
                  ? 'Location unavailable'
                  : value.drive] ??=
              [])
          .add(game);
      if (value?.bytes != null) {
        measured.add(value!);
        if (c.storageService?.stale(value) == true) stale++;
      } else if (value != null || !busy) {
        unavailable++;
      }
    }
    final drives = groups.keys.toList()..sort();
    return ListView(
      children: [
        PageHeading(
          'Storage Overview',
          'Installation sizes for games in My Library.',
          action: FilledButton.tonalIcon(
            onPressed: c.games.isEmpty || (busy && cancel)
                ? null
                : busy
                ? () => setState(() => cancel = true)
                : () => load(refresh: true),
            icon: Icon(busy ? Icons.stop_circle_outlined : Icons.refresh),
            label: Text(busy ? 'Cancel' : 'Refresh sizes'),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tracked library size',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  storageSize(
                    measured.isEmpty ? null : trackedStorageBytes(measured),
                  ),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  '${measured.length} measured · $stale stale · $unavailable unavailable',
                ),
                const Text(
                  'Known logical file sizes in Windows-style units. Shared folders count once.',
                ),
              ],
            ),
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: count == 0 ? null : completed / count),
          Text(
            cancel
                ? 'Finishing the current check…'
                : 'Checked $completed of $count games',
          ),
        ] else if (cancel)
          const Text('Refresh cancelled. Completed results are retained.'),
        const SizedBox(height: 12),
        if (c.games.isEmpty)
          const Text('Add games to My Library to see their installation sizes.')
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sort),
              label: Text(largest ? 'Largest first' : 'Smallest first'),
              onPressed: () => setState(() => largest = !largest),
            ),
          ),
          for (final drive in drives) ...[
            const SizedBox(height: 16),
            SectionTitle(drive),
            ...((groups[drive]!..sort((a, b) {
                  final x = results[a.appId]?.bytes,
                      y = results[b.appId]?.bytes;
                  if (x == null && y != null) return 1;
                  if (y == null && x != null) return -1;
                  final order = (x ?? 0).compareTo(y ?? 0);
                  return order == 0
                      ? a.title.compareTo(b.title)
                      : largest
                      ? -order
                      : order;
                }))
                .map((game) {
                  final value = results[game.appId];
                  final old =
                      value?.bytes != null &&
                      c.storageService?.stale(value!) == true;
                  return Card(
                    child: ListTile(
                      title: Text(game.title),
                      subtitle: Text(
                        value?.bytes == null
                            ? value?.message ??
                                  (busy ? 'Checking…' : 'Unavailable')
                            : '${storageSize(value!.bytes)}${old ? ' · Stale' : ''}',
                      ),
                      onTap: () => widget.onOpen(game),
                      trailing: IconButton(
                        tooltip: 'Open installation folder',
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: value == null || value.path.isEmpty
                            ? null
                            : () => c.openGameLocation(game.appId),
                      ),
                    ),
                  );
                })),
          ],
        ],
      ],
    );
  }
}
