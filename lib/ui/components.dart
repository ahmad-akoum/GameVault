import 'dart:io';
import 'package:flutter/material.dart';
import '../models/game.dart';
import 'artwork_image.dart';
import 'responsive.dart';
import '../services/steam_updates.dart';
import 'steam_update_indicator.dart';

class GameArtwork extends StatelessWidget {
  const GameArtwork({
    super.key,
    this.path,
    this.url,
    required this.title,
    this.fit = BoxFit.cover,
    this.fullResolution = false,
  });
  final String? path, url;
  final String title;
  final BoxFit fit;
  final bool fullResolution;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget fallback() => LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 100 || constraints.maxHeight < 130) {
          return ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.videogame_asset_outlined,
                size: 22,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videogame_asset_outlined,
                    size: 32,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        ImageProvider sized(ImageProvider source) {
          if (fullResolution ||
              !constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return source;
          }
          return ArtworkImage(
            source,
            artworkBucket(constraints.maxWidth * dpr),
            artworkBucket(constraints.maxHeight * dpr),
            fit,
          );
        }

        Widget remote() => url == null
            ? fallback()
            : Image(
                image: sized(NetworkImage(url!)),
                fit: fit,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, error, stack) => fallback(),
              );
        if (path == null) return remote();
        return Image(
          image: sized(FileImage(File(path!))),
          fit: fit,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, error, stack) => remote(),
        );
      },
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AdaptiveRow(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: AdaptiveRow(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({
    super.key,
    required this.onScan,
    this.filtered = false,
    this.favorites = false,
  });
  final VoidCallback onScan;
  final bool filtered, favorites;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 510),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                favorites ? Icons.favorite_border : Icons.shelves,
                size: 55,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 22),
              Text(
                filtered
                    ? 'No games match this view'
                    : favorites
                    ? 'Keep your favorites close'
                    : 'A library that’s yours',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                filtered
                    ? 'Try another search or status filter.'
                    : favorites
                    ? 'Mark a game with the heart icon and it will appear here.'
                    : 'Find the games installed in your Steam libraries, then choose the ones you want to keep in GameVault.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!filtered && !favorites) ...[
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Find Steam games'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Local library • No account required',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class GameTile extends StatefulWidget {
  const GameTile({
    super.key,
    required this.game,
    required this.onOpen,
    required this.onFavorite,
    this.update = SteamUpdateEvidence.unknown,
  });
  final VaultGame game;
  final SteamUpdateEvidence update;
  final VoidCallback onOpen, onFavorite;
  @override
  State<GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<GameTile> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GameArtwork(
                    path: g.coverPath,
                    title: g.title,
                    fit: g.artwork?.coverContained == true
                        ? BoxFit.contain
                        : BoxFit.cover,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.onOpen,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hover ? scheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hover || g.favorite)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Material(
                      color: const Color(0xdd17191d),
                      borderRadius: BorderRadius.circular(4),
                      child: IconButton(
                        tooltip: g.favorite
                            ? 'Remove favorite'
                            : 'Add favorite',
                        onPressed: widget.onFavorite,
                        icon: Icon(
                          g.favorite ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: Colors.white,
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                      ),
                    ),
                  ),
                if (widget.update.badge != null)
                  Positioned(
                    top: 7,
                    left: 7,
                    right: 45,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SteamUpdateBadge(evidence: widget.update),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InkWell(
              onTap: widget.onOpen,
              child: Text(
                g.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                color: g.status == GameStatus.playing
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  g.status.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (g.hltb != null && g.hltb!.main > 0)
                Text(
                  '${g.hltb!.main.round()}h main',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class VaultGrid extends StatelessWidget {
  const VaultGrid({
    super.key,
    required this.games,
    required this.onOpen,
    required this.onFavorite,
    this.shrinkWrap = false,
    this.updates = const {},
  });
  final List<VaultGame> games;
  final Map<int, SteamUpdateEvidence> updates;
  final ValueChanged<VaultGame> onOpen, onFavorite;
  final bool shrinkWrap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wrap = shrinkWrap || !c.hasBoundedHeight;
      final count = (c.maxWidth / 205).floor().clamp(1, 8);
      final width = (c.maxWidth - (count - 1) * 20) / count;
      return GridView.builder(
        shrinkWrap: wrap,
        physics: wrap ? const NeverScrollableScrollPhysics() : null,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: 20,
          mainAxisSpacing: 24,
          mainAxisExtent:
              width * 1.48 + 56 * MediaQuery.textScalerOf(context).scale(1),
        ),
        itemCount: games.length,
        itemBuilder: (_, i) => GameTile(
          game: games[i],
          update: updates[games[i].appId] ?? SteamUpdateEvidence.unknown,
          onOpen: () => onOpen(games[i]),
          onFavorite: () => onFavorite(games[i]),
        ),
      );
    },
  );
}
