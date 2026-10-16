import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'theme.dart';

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
        const SectionTitle('Appearance'),
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
    final s = controller.settings;
    final brightness = Theme.of(context).brightness;
    var picked = switch (field) {
      'Accent' => s.accent,
      'Background' =>
        s.background ?? Theme.of(context).colorScheme.surface.toARGB32(),
      _ =>
        s.surface ?? Theme.of(context).colorScheme.surfaceContainer.toARGB32(),
    };
    final hex = TextEditingController(
      text: picked.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
    );
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final preview = s.copy(
            accent: field == 'Accent' ? picked : null,
            background: field == 'Background' ? picked : null,
            surface: field == 'Surface' ? picked : null,
          );
          return AlertDialog(
            title: Text('Custom $field color'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Theme(
                      data: vaultTheme(
                        brightness,
                        preview.accent,
                        background: preview.background,
                        surface: preview.surface,
                      ),
                      child: const _Preview(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: hex,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[a-fA-F0-9]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Hex color',
                        prefixText: '#',
                      ),
                      onChanged: (v) => update(() {
                        if (v.length == 6) {
                          picked = 0xff000000 | int.parse(v, radix: 16);
                        }
                      }),
                    ),
                    for (var channel = 0; channel < 3; channel++)
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(['Red', 'Green', 'Blue'][channel]),
                          ),
                          Expanded(
                            child: Slider(
                              label: '${(picked >> (16 - channel * 8)) & 255}',
                              value: ((picked >> (16 - channel * 8)) & 255)
                                  .toDouble(),
                              max: 255,
                              divisions: 255,
                              onChanged: (v) => update(() {
                                final shift = 16 - channel * 8;
                                picked =
                                    (picked & ~(255 << shift)) |
                                    (v.round() << shift);
                                hex.text = picked
                                    .toRadixString(16)
                                    .substring(2)
                                    .toUpperCase();
                              }),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: hex.text.length == 6
                    ? () => Navigator.pop(context, picked)
                    : null,
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    hex.dispose();
    if (chosen != null) {
      // Preserve any unrelated settings changed while the dialog was open.
      await controller.setSettings(
        controller.settings.copy(
          accent: field == 'Accent' ? chosen : null,
          background: field == 'Background' ? chosen : null,
          surface: field == 'Surface' ? chosen : null,
        ),
      );
    }
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
