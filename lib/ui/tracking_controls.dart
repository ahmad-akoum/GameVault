import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';

import 'components.dart';

import 'steam_update_indicator.dart';

enum TrackingSection { summary, collections, settings }

class TrackingControls extends StatelessWidget {
  const TrackingControls({
    super.key,
    required this.controller,
    required this.game,
    this.section = TrackingSection.summary,
  });
  final VaultController controller;
  final VaultGame game;
  final TrackingSection section;
  @override
  Widget build(BuildContext context) {
    final c = controller, g = game;
    final update = g.isSteam ? c.steamUpdates[g.appId] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section == TrackingSection.summary) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (c.running(g.appId))
                const Chip(
                  avatar: Icon(Icons.videogame_asset_outlined, size: 18),
                  label: Text('Running'),
                )
              else if (update?.badge != null)
                SteamUpdateAction(
                  evidence: update!,
                  onOpen: () => c.openGameLocation(g.appId, steam: true),
                )
              else
                FilledButton.icon(
                  onPressed:
                      c.running(g.appId) ||
                          c.pendingLaunches.containsKey(g.appId)
                      ? null
                      : () => c.launch(g.appId),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play Game'),
                ),
            ],
          ),
          if (!c.running(g.appId) && update?.badge != null) ...[
            const SizedBox(height: 6),
            Text(
              'Opens this game in Steam. Start the update there manually.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
        if (section == TrackingSection.settings) ...[
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Tracking executable'),
            subtitle: Text(
              g.executablePath ??
                  'Automatic • visible game processes inside its installation folder',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              const Text(
                'If automatic detection misses the game or identifies a launcher, select the actual game executable. Protected processes and launchers outside the game folder may need this override.',
              ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () async {
                      final file = await openFile(
                        acceptedTypeGroups: [
                          const XTypeGroup(
                            label: 'Game executable',
                            extensions: ['exe'],
                          ),
                        ],
                      );
                      if (file != null) {
                        await c.update(
                          g.appId,
                          (v) => v.copy(executablePath: file.path),
                        );
                      }
                    },
                    child: const Text('Choose executable'),
                  ),
                  if (!g.isManual && g.executablePath != null)
                    TextButton(
                      onPressed: () => c.update(
                        g.appId,
                        (v) => v.copy(clearExecutable: true),
                      ),
                      child: const Text('Use automatic detection'),
                    ),
                ],
              ),
            ],
          ),
        ],
        if (section == TrackingSection.collections) ...[
          const SizedBox(height: 24),
          const SectionTitle('Collections'),
          if (c.settings.collections.isEmpty)
            const Text(
              'Create a collection from the sidebar to organize this game.',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: c.settings.collections
                .map(
                  (name) => FilterChip(
                    label: Text(name),
                    selected: g.collections.contains(name),
                    onSelected: (selected) => c.update(
                      g.appId,
                      (v) => v.copy(
                        collections: selected
                            ? {...v.collections, name}.toList()
                            : v.collections.where((n) => n != name).toList(),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class TrackingSettings extends StatelessWidget {
  const TrackingSettings({super.key, required this.controller});
  final VaultController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Playtime & activity'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Track game sessions'),
          subtitle: const Text(
            'Keep GameVault open while playing. Saves a checkpoint every 15 seconds.',
          ),
          value: c.settings.trackingEnabled,
          onChanged: (v) => c.setSettings(c.settings.copy(trackingEnabled: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use activity-adjusted time in statistics'),
          subtitle: const Text(
            'Both full session time and active time are always retained.',
          ),
          value: c.settings.activityAdjusted,
          onChanged: (v) => c.setSettings(c.settings.copy(activityAdjusted: v)),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                key: ValueKey('idle-${c.settings.idleThreshold}'),
                initialValue: c.settings.idleThreshold,
                decoration: const InputDecoration(labelText: 'Idle threshold'),
                items:
                    ({
                          ...{30, 60, 120, 300, 600},
                          c.settings.idleThreshold,
                        }.toList()..sort())
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n seconds'),
                          ),
                        )
                        .toList(),
                onChanged: (v) =>
                    c.setSettings(c.settings.copy(idleThreshold: v)),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                key: ValueKey('focus-${c.settings.focusGrace}'),
                initialValue: c.settings.focusGrace,
                decoration: const InputDecoration(
                  labelText: 'Unfocused grace period',
                ),
                items:
                    ({
                          ...{0, 5, 10, 30, 60},
                          c.settings.focusGrace,
                        }.toList()..sort())
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n seconds'),
                          ),
                        )
                        .toList(),
                onChanged: (v) => c.setSettings(c.settings.copy(focusGrace: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Activity uses Windows keyboard/mouse idle time and XInput controller state. Cutscenes, reading, held keys and unsupported controllers may appear idle. Use full session time when that suits the game. No keystrokes or input contents are recorded.',
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}
