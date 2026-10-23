import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'responsive.dart';
import 'activity_pages.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onScan,
    required this.onLibrary,
  });
  final VaultController controller;
  final ValueChanged<VaultGame> onOpen;
  final VoidCallback onScan;
  final ValueChanged<GameStatus?> onLibrary;
  @override
  Widget build(BuildContext context) {
    final games = controller.games;
    if (games.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading('Home', 'Your games. Your pace.'),
          Expanded(child: EmptyLibrary(onScan: onScan)),
        ],
      );
    }
    final playing = games.where((g) => g.status == GameStatus.playing).toList();
    final recent = [...games]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final recentlyPlayed =
        games
            .where((g) => controller.tracker.lastPlayed(g.appId) != null)
            .toList()
          ..sort(
            (a, b) => controller.tracker
                .lastPlayed(b.appId)!
                .compareTo(controller.tracker.lastPlayed(a.appId)!),
          );
    return ListView(
      children: [
        PageHeading(
          'Home',
          'A good day for your next adventure.',
          action: OutlinedButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add games'),
          ),
        ),
        ActivitySummary(controller: controller),
        const SizedBox(height: 24),
        AdaptiveRow(
          children: [
            _stat(
              context,
              'In your vault',
              games.length,
              () => onLibrary(null),
            ),
            _stat(
              context,
              'Playing',
              playing.length,
              () => onLibrary(GameStatus.playing),
            ),
            _stat(
              context,
              'Play later',
              games.where((g) => g.status == GameStatus.backlog).length,
              () => onLibrary(GameStatus.backlog),
            ),
            _stat(
              context,
              'Finished',
              games
                  .where(
                    (g) =>
                        g.status == GameStatus.completed ||
                        g.status == GameStatus.completionist,
                  )
                  .length,
              () => onLibrary(GameStatus.completed),
            ),
          ],
        ),
        const SizedBox(height: 32),
        if (recentlyPlayed.isNotEmpty) ...[
          const SectionTitle('Recently played'),
          VaultGrid(
            updates: controller.steamUpdates,
            games: recentlyPlayed.take(4).toList(),
            onOpen: onOpen,
            onFavorite: (g) => controller.update(
              g.appId,
              (current) => current.copy(favorite: !current.favorite),
            ),
            shrinkWrap: true,
          ),
          const SizedBox(height: 28),
        ],
        if (playing.isNotEmpty) ...[
          const SectionTitle('In rotation'),
          VaultGrid(
            updates: controller.steamUpdates,
            games: playing.take(4).toList(),
            onOpen: onOpen,
            onFavorite: (g) => controller.update(
              g.appId,
              (current) => current.copy(favorite: !current.favorite),
            ),
            shrinkWrap: true,
          ),
          const SizedBox(height: 32),
        ],
        SectionTitle(
          'Recently added',
          action: TextButton(
            onPressed: () => onLibrary(null),
            child: const Text('View library →'),
          ),
        ),
        VaultGrid(
          updates: controller.steamUpdates,
          games: recent.take(8).toList(),
          onOpen: onOpen,
          onFavorite: (g) => controller.update(
            g.appId,
            (current) => current.copy(favorite: !current.favorite),
          ),
          shrinkWrap: true,
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    int value,
    VoidCallback onTap,
  ) => Expanded(
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    ),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onScan,
    this.favorites = false,
    this.initialStatus,
  });
  final VaultController controller;
  final ValueChanged<VaultGame> onOpen;
  final VoidCallback onScan;
  final bool favorites;
  final GameStatus? initialStatus;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String search = '', sort = 'Recently added';
  GameStatus? status;
  bool favoriteOnly = false;
  final searchFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    status = widget.initialStatus;
  }

  @override
  void dispose() {
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var games = widget.controller.games
        .where(
          (g) =>
              g.title.toLowerCase().contains(search.toLowerCase()) &&
              (status == null ||
                  g.status == status ||
                  (status == GameStatus.completed &&
                      g.status == GameStatus.completionist)) &&
              (!(widget.favorites || favoriteOnly) || g.favorite),
        )
        .toList();
    games.sort(
      (a, b) => sort == 'Title A–Z'
          ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : sort == 'Most played'
          ? widget.controller
                .played(b.appId)
                .compareTo(widget.controller.played(a.appId))
          : sort == 'Last played'
          ? (widget.controller.tracker.lastPlayed(b.appId) ?? DateTime(1970))
                .compareTo(
                  widget.controller.tracker.lastPlayed(a.appId) ??
                      DateTime(1970),
                )
          : sort == 'Main story length'
          ? (a.hltb?.main ?? double.infinity).compareTo(
              b.hltb?.main ?? double.infinity,
            )
          : b.addedAt.compareTo(a.addedAt),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            searchFocus.requestFocus,
      },
      child: ResponsivePage(
        children: [
          PageHeading(
            widget.favorites ? 'Favorites' : 'My Library',
            '${games.length} ${games.length == 1 ? 'game' : 'games'} • Curated by you',
            action: OutlinedButton.icon(
              onPressed: widget.onScan,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add games'),
            ),
          ),
          AdaptiveRow(
            breakpoint: 700,
            children: [
              Expanded(
                child: TextField(
                  focusNode: searchFocus,
                  onChanged: (v) => setState(() => search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search your games',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<GameStatus?>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All games'),
                    ),
                    ...GameStatus.values.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                    ),
                  ],
                  onChanged: (v) => setState(() => status = v),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: sort,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sort by'),
                  items: ['Recently added', 'Title A–Z', 'Main story length']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => sort = v!),
                ),
              ),
              if (!widget.favorites) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Favorites only',
                  isSelected: favoriteOnly,
                  selectedIcon: const Icon(Icons.favorite),
                  onPressed: () => setState(() => favoriteOnly = !favoriteOnly),
                  icon: const Icon(Icons.favorite_border),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: games.isEmpty
                ? EmptyLibrary(
                    onScan: widget.onScan,
                    filtered:
                        search.isNotEmpty || status != null || favoriteOnly,
                    favorites: widget.favorites,
                  )
                : VaultGrid(
                    updates: widget.controller.steamUpdates,
                    games: games,
                    onOpen: widget.onOpen,
                    onFavorite: (g) => widget.controller.update(
                      g.appId,
                      (current) => current.copy(favorite: !current.favorite),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
