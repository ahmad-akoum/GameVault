import 'package:flutter/material.dart';

import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'responsive.dart';
import 'tracking_controls.dart';
import 'appearance_controls.dart';
import 'artwork_viewer.dart';
import 'artwork_manager.dart';
import 'activity_pages.dart';
import '../services/steam_installation.dart';
import '../services/steam_updates.dart';
import 'steam_update_indicator.dart';

class DetailsPage extends StatefulWidget {
  const DetailsPage({
    super.key,
    required this.controller,
    required this.id,
    required this.onBack,
  });
  final VaultController controller;
  final int id;
  final VoidCallback onBack;
  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  bool allSessions = false;
  bool showCandidates = false;
  late final TextEditingController query;
  @override
  void initState() {
    super.initState();
    query = TextEditingController(
      text:
          widget.controller.game(widget.id)?.hltb?.title ??
          widget.controller.game(widget.id)?.title ??
          '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.checkInstallation(widget.id);
        if (widget.controller.platform != null) {
          widget.controller.refreshSteamUpdates();
        }
      }
    });
  }

  @override
  void didUpdateWidget(DetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      allSessions = false;
      showCandidates = false;
      query.text =
          widget.controller.game(widget.id)?.hltb?.title ??
          widget.controller.game(widget.id)?.title ??
          '';
      widget.controller.checkInstallation(widget.id);
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final g = c.game(widget.id);
    if (g == null) {
      return Center(
        child: OutlinedButton(
          onPressed: widget.onBack,
          child: const Text('Back to library'),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final profile = c.settings.profileSize;
    final gap = profile == ProfileSize.compact
        ? 14.0
        : profile == ProfileSize.expanded
        ? 34.0
        : 22.0;
    return ListView(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to library'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ProfileSizeControl(
              value: profile,
              onChanged: (v) => c.setSettings(c.settings.copy(profileSize: v)),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Manage Artwork'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ArtworkManager(controller: c, id: g.appId),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          key: const ValueKey('profileArtwork'),
          height: profileArtworkHeight(
            profile,
            MediaQuery.sizeOf(context).width,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Tooltip(
              message: 'Enlarge artwork',
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      ArtworkViewer(title: g.title, path: g.profileArtworkPath),
                ),
                child: Semantics(
                  button: true,
                  label: 'Enlarge artwork',
                  child: GameArtwork(
                    path: g.profileArtworkPath,
                    fit: g.artwork?.heroContained == true
                        ? BoxFit.contain
                        : BoxFit.cover,
                    title: g.title,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: gap),
        Text(g.title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(
          [
            g.isManual ? 'Local game' : 'Steam',
            'Windows',
            if (g.release != null) g.release!,
            ...g.genres,
          ].join('  •  '),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: gap),
        TrackingControls(controller: c, game: g),
        if (c.steamUpdates[g.appId]?.badge != null)
          SteamUpdateSummary(
            evidence: c.steamUpdates[g.appId]!,
            onOpen: () => c.openGameLocation(g.appId, steam: true),
          ),
        SizedBox(height: gap),
        const SectionTitle('Recent sessions'),
        if (!c.tracker.sessions.any((s) => s.gameId == g.appId))
          const Text(
            'No recorded sessions yet. Keep GameVault open while playing.',
          ),
        ...c.tracker.sessions.reversed
            .where((s) => s.gameId == g.appId)
            .take(allSessions ? c.tracker.sessions.length : 2)
            .map((s) => SessionRow(session: s, showTitle: false)),
        if (c.tracker.sessions.where((s) => s.gameId == g.appId).length > 2)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => allSessions = !allSessions),
              child: Text(allSessions ? 'Show less' : 'View all sessions'),
            ),
          ),
        TrackingControls(
          controller: c,
          game: g,
          section: TrackingSection.progress,
        ),
        SizedBox(height: gap),
        ExpansionTile(
          key: const PageStorageKey('gameSettings'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Game Settings / Installation / Tracking'),
          children: [
            TrackingControls(
              controller: c,
              game: g,
              section: TrackingSection.settings,
            ),
            Text(
              'Installation: ${c.installations[g.appId]?.status.label ?? InstallationStatus.unknown.label}',
            ),
            if (c.installations[g.appId] != null)
              Text(c.installations[g.appId]!.message),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!g.isManual)
                  OutlinedButton.icon(
                    onPressed: c.refreshingInstallation.contains(g.appId)
                        ? null
                        : () => c.refreshInstallation(g.appId),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Installation'),
                  ),
                OutlinedButton(
                  onPressed: () => c.openGameLocation(g.appId),
                  child: const Text('Open Game Directory'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      c.openGameLocation(g.appId, executable: true),
                  child: const Text('Open EXE Location'),
                ),
              ],
            ),
            if (!g.isManual) ...[
              const SizedBox(height: 16),
              const SectionTitle('Game Update Center'),
              SteamUpdatePanel(
                evidence:
                    c.steamUpdates[g.appId] ?? SteamUpdateEvidence.unknown,
                onOpen: () => c.openGameLocation(g.appId, steam: true),
                onRefresh: () => c.refreshSteamUpdates(),
              ),
              if (c.installations[g.appId]?.buildId != null)
                Text('Installed build: ${c.installations[g.appId]!.buildId}'),
              if (c.installations[g.appId]?.updated != null)
                Text(
                  'Steam manifest LastUpdated: ${c.installations[g.appId]!.updated!.toLocal()}',
                ),
            ],
          ],
        ),
        SizedBox(height: gap),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 185,
              child: DropdownButtonFormField<GameStatus>(
                isExpanded: true,
                key: ValueKey('${g.appId}-${g.status.name}'),
                initialValue: g.status,
                decoration: const InputDecoration(labelText: 'Personal status'),
                items: GameStatus.values
                    .map(
                      (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                    )
                    .toList(),
                onChanged: (s) =>
                    c.update(g.appId, (current) => current.copy(status: s)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => c.update(
                g.appId,
                (current) => current.copy(favorite: !current.favorite),
              ),
              icon: Icon(
                g.favorite ? Icons.favorite : Icons.favorite_border,
                size: 18,
              ),
              label: Text(g.favorite ? 'Favorited' : 'Favorite'),
            ),
            OutlinedButton.icon(
              onPressed: g.isManual || c.busy.contains(g.appId)
                  ? null
                  : () => c.refreshMetadata(g.appId),
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Refresh artwork & metadata'),
            ),
          ],
        ),
        SizedBox(height: gap),
        const Divider(),
        const SizedBox(height: 28),
        AdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'HOW LONG TO BEAT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.7,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: g.hltbState == HltbState.loading
                  ? null
                  : () => c.lookup(g.appId),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (g.hltb != null) ...[
          AdaptiveRow(
            children: [
              _time(context, 'Main Story', g.hltb!.main),
              _time(context, 'Main + Sides', g.hltb!.extras),
              _time(context, 'Completionist', g.hltb!.complete),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Source: HowLongToBeat • ${g.hltb!.title}${g.hltbUpdated != null ? ' • Retrieved ${g.hltbUpdated!.toLocal().toString().split(' ').first}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          SelectableText(
            g.hltb!.url,
            style: TextStyle(fontSize: 12, color: scheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            'Community completion times, not your personal playtime or story progress.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (g.hltbState == HltbState.loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: AdaptiveRow(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  g.hltb == null
                      ? 'Searching HowLongToBeat…'
                      : 'Refreshing; saved information is shown above…',
                ),
              ],
            ),
          ),
        if (g.hltbState != HltbState.matched &&
            g.hltbState != HltbState.loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: AdaptiveRow(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  g.hltbState == HltbState.ambiguous
                      ? Icons.rule
                      : Icons.info_outline,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    g.hltbState == HltbState.pending
                        ? 'Search for a game below or refresh its saved match.'
                        : '${(g.hltbMessage?.contains('temporarily unavailable pending') == true ? 'Search or refresh to check current availability.' : g.hltbMessage) ?? 'No completion information available.'}${g.hltb != null ? ' Previously saved information is shown above.' : ''}',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        ExpansionTile(
          initiallyExpanded:
              g.hltbState == HltbState.ambiguous ||
              g.hltbState == HltbState.noMatch,
          tilePadding: EdgeInsets.zero,
          title: const Text('Find or change the HowLongToBeat match'),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              child: AdaptiveRow(
                children: [
                  Expanded(
                    child: TextField(
                      controller: query,
                      onSubmitted: g.hltbState == HltbState.loading
                          ? null
                          : (text) {
                              setState(() => showCandidates = true);
                              c.lookup(g.appId, query: text);
                            },
                      decoration: const InputDecoration(
                        labelText: 'Game title on HowLongToBeat',
                        hintText: 'Try an alternate title',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: g.hltbState == HltbState.loading
                        ? null
                        : () {
                            setState(() => showCandidates = true);
                            c.lookup(g.appId, query: query.text);
                          },
                    child: const Text('Search'),
                  ),
                ],
              ),
            ),
            if (g.candidates.isNotEmpty &&
                (showCandidates || g.candidates.isNotEmpty))
              ...g.candidates.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.title),
                  subtitle: Text(
                    '${e.year != null && e.year! > 0 ? '${e.year} • ' : ''}${e.main > 0 ? '${e.main.toStringAsFixed(1)} hours main story' : 'Main story time unavailable'}',
                  ),
                  trailing: OutlinedButton(
                    onPressed: () {
                      setState(() => showCandidates = false);
                      c.selectMatch(g.appId, e);
                    },
                    child: const Text('Use this match'),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: gap),
        const Divider(),
        SizedBox(height: gap),
        const SectionTitle('Critic ratings'),
        const Text(
          'Ratings are not connected. An authorized Metacritic or OpenCritic data source is required; no score is inferred.',
        ),
        const SizedBox(height: 24),
        SectionTitle(g.isManual ? 'Local installation' : 'Steam installation'),
        if (!g.isManual) _metadata(context, 'Steam AppID', '${g.appId}'),
        if (g.developer != null) _metadata(context, 'Developer', g.developer!),
        if (g.publisher != null) _metadata(context, 'Publisher', g.publisher!),
        _metadata(context, 'Library folder', g.libraryPath),
        _metadata(context, 'Installation folder', g.installPath),
        if (g.metadataMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              g.metadataMessage!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 20),
        AdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'Remove this entry from your personal library.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => _remove(g),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove from GameVault'),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _time(BuildContext context, String label, double hours) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineMedium,
              children: [
                TextSpan(
                  text: hours > 0
                      ? hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)
                      : '—',
                ),
                if (hours > 0)
                  TextSpan(
                    text: ' hrs',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _metadata(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AdaptiveRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 155,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
  Future<void> _remove(VaultGame g) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from GameVault?'),
        content: Text(
          'Remove ${g.title} and its personal status from your vault?\n\nThe Steam game and its files will remain installed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove entry'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.controller.remove(g.appId);
      if (mounted && widget.controller.game(g.appId) == null) {
        widget.onBack();
      }
    }
  }
}

/// Keep desktop sizes; constrain tall Expanded artwork in narrow Snap slots.
double profileArtworkHeight(ProfileSize size, double width) {
  final desired = switch (size) {
    ProfileSize.compact => 180.0,
    ProfileSize.comfortable => 260.0,
    ProfileSize.expanded => 420.0,
  };
  return width < 700
      ? desired.clamp(0.0, (width - 48).clamp(120.0, 650.0) * 9 / 16)
      : desired;
}
