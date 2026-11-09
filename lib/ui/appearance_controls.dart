import 'package:flutter/material.dart';
import 'theme_editor.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';

const appearancePresets = <String, (int, int, int)>{
  'Cobalt': (0xff78aaff, 0xff101725, 0xff192840),
  'Crimson': (0xffff7e90, 0xff201217, 0xff321c25),
  'Emerald': (0xff6ed8ae, 0xff0e1b18, 0xff18302a),
  'Amethyst': (0xffbf9aff, 0xff191324, 0xff2b203c),
  'Obsidian': (0xffd0d5df, 0xff121315, 0xff24262a),
  'Midnight': (0xff83cddd, 0xff0c1420, 0xff152638),
};

class AppearanceControls extends StatelessWidget {
  const AppearanceControls({super.key, required this.controller});
  final VaultController controller;
  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Appearance',
          action: FilledButton.tonalIcon(
            icon: const Icon(Icons.palette_outlined),
            label: const Text('Theme studio'),
            onPressed: () => _pick(context, 'Accent'),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final mode in AppearanceMode.values)
              ChoiceChip(
                label: Text(switch (mode) {
                  AppearanceMode.dark => 'Dark',
                  AppearanceMode.light => 'Light',
                  AppearanceMode.system => 'System',
                }),
                selected: s.theme == mode,
                onSelected: (_) => controller.setSettings(s.copy(theme: mode)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Color presets', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in appearancePresets.entries)
              ChoiceChip(
                label: Text(entry.key),
                avatar: CircleAvatar(
                  backgroundColor: Color(entry.value.$1),
                  radius: 7,
                ),
                selected:
                    s.accent == entry.value.$1 &&
                    s.background == entry.value.$2 &&
                    s.surface == entry.value.$3,
                onSelected: (_) => controller.setSettings(
                  s.copy(
                    accent: entry.value.$1,
                    background: entry.value.$2,
                    surface: entry.value.$3,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final field in ['Accent', 'Background', 'Surface'])
              OutlinedButton.icon(
                onPressed: () => _pick(context, field),
                icon: Icon(
                  Icons.palette_outlined,
                  color: switch (field) {
                    'Accent' => scheme.primary,
                    'Background' => scheme.onSurfaceVariant,
                    _ => scheme.onSurfaceVariant,
                  },
                ),
                label: Text('Custom $field'),
              ),
            TextButton(
              onPressed: () => controller.setSettings(
                s.copy(resetColors: true, accent: 0xffb8d96e),
              ),
              child: const Text('Reset colors'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Background and surface hues adapt to Dark, Light, or System mode for readable contrast.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        const _Preview(),
        const SizedBox(height: 24),
        Text(
          'Game profile size',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        ProfileSizeControl(
          value: s.profileSize,
          onChanged: (v) => controller.setSettings(s.copy(profileSize: v)),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, String field) async {
    final chosen = await showDialog<VaultSettings>(
      context: context,
      builder: (_) => ThemeEditor(
        settings: controller.settings,
        initialRole: [
          'Accent',
          'Background',
          'Surface',
        ].indexOf(field).clamp(0, 2),
      ),
    );
    if (chosen == null) return;
    await controller.setSettings(
      controller.settings
          .copy(resetColors: true)
          .copy(
            theme: chosen.theme,
            accent: chosen.accent,
            background: chosen.background,
            surface: chosen.surface,
            gradient: chosen.gradient,
          ),
    );
  }
}

class ProfileSizeControl extends StatelessWidget {
  const ProfileSizeControl({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ProfileSize value;
  final ValueChanged<ProfileSize> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final size in ProfileSize.values)
        ChoiceChip(
          label: Text(switch (size) {
            ProfileSize.compact => 'Compact',
            ProfileSize.comfortable => 'Comfortable',
            ProfileSize.expanded => 'Expanded',
          }),
          selected: size == value,
          onSelected: (_) => onChanged(size),
        ),
    ],
  );
}

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.videogame_asset_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your next adventure',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Selected actions', style: TextStyle(color: scheme.primary)),
        ],
      ),
    );
  }
}
