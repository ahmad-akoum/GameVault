import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'tracking_controls.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onScan,
  });
  final VaultController controller;
  final VoidCallback onScan;
  static const accents = [
    0xffb8d96e,
    0xff79b8e8,
    0xffb59ae9,
    0xffe9a46d,
    0xffe87d87,
    0xff6dc8b0,
  ];
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const PageHeading('Settings', 'Make GameVault feel at home.'),
        TrackingSettings(controller: c),
        const SectionTitle('Appearance'),
        Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SegmentedButton<AppearanceMode>(
              segments: const [
                ButtonSegment(
                  value: AppearanceMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 16),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: AppearanceMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 16),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: AppearanceMode.system,
                  icon: Icon(Icons.desktop_windows_outlined, size: 16),
                  label: Text('System'),
                ),
              ],
              selected: {c.settings.theme},
              onSelectionChanged: (v) =>
                  c.setSettings(c.settings.copy(theme: v.single)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(
                'Accent color',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Wrap(
              spacing: 10,
              children: accents
                  .map(
                    (color) => Tooltip(
                      message: const [
                        'Sage',
                        'Blue',
                        'Lilac',
                        'Amber',
                        'Rose',
                        'Teal',
                      ][accents.indexOf(color)],
                      child: InkWell(
                        borderRadius: BorderRadius.circular(5),
                        onTap: () =>
                            c.setSettings(c.settings.copy(accent: color)),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(color),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: c.settings.accent == color
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: c.settings.accent == color
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Color(0xff17191d),
                                )
                              : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(width: 14),
            OutlinedButton(
              onPressed: () => _customColor(context),
              child: const Text('Custom…'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Accents highlight selections and actions. Your library surfaces stay neutral.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 28),
        SectionTitle(
          'Steam library folders',
          action: OutlinedButton.icon(
            onPressed: () => _addFolder(context),
            icon: const Icon(Icons.create_new_folder_outlined, size: 17),
            label: const Text('Add folder'),
          ),
        ),
        Text(
          'Choose a Steam installation or SteamLibrary folder. Scans also read Steam’s library configuration to find linked libraries.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        if (c.settings.paths.isEmpty)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              'No folders added yet. Add your Steam library to get started.',
            ),
          ),
        ...c.settings.paths.map(
          (path) => Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 23,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(child: SelectableText(path)),
                IconButton(
                  tooltip: 'Stop scanning this folder',
                  onPressed: () => c.setSettings(
                    c.settings.copy(
                      paths: c.settings.paths.where((e) => e != path).toList(),
                    ),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: c.settings.paths.isEmpty || c.scanning ? null : onScan,
            icon: const Icon(Icons.manage_search, size: 19),
            label: const Text('Scan libraries'),
          ),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 28),
        const SectionTitle('Local data'),
        const Text(
          'Your library, preferences and retrieved completion times are saved locally. Cached artwork remains available offline.',
        ),
        const SizedBox(height: 12),
        SelectableText(
          c.store.directory.path,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(
          'To back up GameVault, close the app and copy this data folder. Keep the entire Windows release folder together when moving the app.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 30),
        const Divider(),
        const SizedBox(height: 22),
        Text('GameVault 1.0.0', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'A personal Windows game library. Steam and HowLongToBeat are independent services.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    final text = TextEditingController();
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a Steam library'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select the folder containing steamapps, or enter its path.',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: text,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Library folder',
                        hintText: r'D:\SteamLibrary',
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          Navigator.pop(context, v.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () async {
                      final path = await getDirectoryPath(
                        confirmButtonText: 'Choose library',
                      );
                      if (path != null) {
                        text.text = path;
                      }
                    },
                    child: const Text('Browse…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text.trim());
              }
            },
            child: const Text('Add folder'),
          ),
        ],
      ),
    );
    // Wait for the dialog route transition before disposing its field controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    text.dispose();
    if (chosen == null || chosen.trim().isEmpty) {
      return;
    }
    final normalized = p.normalize(chosen);
    if (!controller.settings.paths.any(
      (e) => p.equals(e.toLowerCase(), normalized.toLowerCase()),
    )) {
      await controller.setSettings(
        controller.settings.copy(
          paths: [...controller.settings.paths, normalized],
        ),
      );
    }
  }

  Future<void> _customColor(BuildContext context) async {
    var picked = Color(controller.settings.accent);
    final hex = TextEditingController(
      text: controller.settings.accent
          .toRadixString(16)
          .substring(2)
          .toUpperCase(),
    );
    String? validation;
    final color = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Custom accent color'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 45, width: double.infinity, color: picked),
                const SizedBox(height: 20),
                TextField(
                  controller: hex,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-fA-F0-9]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Hex color',
                    prefixText: '#',
                    errorText: validation,
                  ),
                  onChanged: (v) {
                    if (v.length == 6) {
                      setLocal(() {
                        picked = Color(0xff000000 | int.parse(v, radix: 16));
                        validation = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                ...['Red', 'Green', 'Blue'].asMap().entries.map((e) {
                  final components = [
                    (picked.r * 255).round(),
                    (picked.g * 255).round(),
                    (picked.b * 255).round(),
                  ];
                  return Row(
                    children: [
                      SizedBox(width: 48, child: Text(e.value)),
                      Expanded(
                        child: Slider(
                          value: components[e.key].toDouble(),
                          max: 255,
                          onChanged: (v) {
                            components[e.key] = v.round();
                            setLocal(() {
                              picked = Color.fromARGB(
                                255,
                                components[0],
                                components[1],
                                components[2],
                              );
                              hex.text = picked
                                  .toARGB32()
                                  .toRadixString(16)
                                  .substring(2)
                                  .toUpperCase();
                              validation = null;
                            });
                          },
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (hex.text.length != 6) {
                  setLocal(() => validation = 'Enter six hex digits.');
                  return;
                }
                Navigator.pop(context, picked.toARGB32());
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    hex.dispose();
    if (color != null) {
      await controller.setSettings(controller.settings.copy(accent: color));
    }
  }
}
