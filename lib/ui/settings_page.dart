import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../state/vault_controller.dart';
import 'components.dart';
import 'responsive.dart';
import 'app_version.dart';
import 'appearance_controls.dart';
import 'tracking_controls.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onScan,
  });
  final VaultController controller;
  final VoidCallback onScan;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const PageHeading('Settings', 'Make GameVault feel at home.'),
        const SectionTitle('General'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Launch GameVault when Windows starts'),
          subtitle: Text(
            c.startup?.allowed == true
                ? c.startupMessage ??
                      'Starts this installed application when you sign in. No administrator access is required.'
                : 'Available in an approved stable installation. Development candidates never change Windows startup.',
          ),
          value: c.startup?.allowed == true && c.startupRegistered,
          onChanged: c.startup?.allowed == true && !c.startupChanging
              ? c.setStartup
              : null,
        ),
        const SizedBox(height: 20),
        TrackingSettings(controller: c),
        AppearanceControls(controller: c),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 28),
        SectionTitle(
          'Steam folders (optional fallback)',
          action: OutlinedButton.icon(
            onPressed: () => _addFolder(context),
            icon: const Icon(Icons.create_new_folder_outlined, size: 17),
            label: const Text('Add folder'),
          ),
        ),
        Text(
          'Steam and its linked libraries are discovered automatically. Add a folder only if automatic discovery misses a library.',
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
              'No manual folders configured. Automatic discovery is still available from Find games.',
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
        const AppVersionLabel(),
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
        scrollable: true,
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
              AdaptiveRow(
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
}
