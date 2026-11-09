import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'responsive.dart';

Future<String?> textPrompt(
  BuildContext context,
  String title, {
  String value = '',
  String label = 'Name',
}) async {
  var text = value;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextFormField(
          initialValue: value,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => text = v,
          onFieldSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (text.trim().isNotEmpty) Navigator.pop(context, text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> importExecutable(
  BuildContext context,
  VaultController controller,
) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'Windows executable', extensions: ['exe']),
    ],
  );
  if (file == null || !context.mounted) return;
  final name = await textPrompt(
    context,
    'Add a game',
    value: p.basenameWithoutExtension(file.path),
    label: 'Game title',
  );
  if (name != null) await controller.addManual(name, file.path);
}

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final VaultController controller;
  final ValueChanged<VaultGame> onOpen;
  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  String? selected;

  Future<void> _manageGames(String name) async {
    final c = widget.controller;
    final games = List.of(c.games);
    final initial = {
      for (final game in games) game.appId: game.collections.contains(name),
    };
    final draft = Map.of(initial);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Games in $name'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final game in games)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(game.title),
                      value: draft[game.appId],
                      onChanged: (value) => setDialogState(
                        () => draft[game.appId] = value == true,
                      ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await c.updateCollectionMembership(name, {
      for (final entry in draft.entries)
        if (entry.value != initial[entry.key]) entry.key: entry.value,
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.settings.collections.contains(selected)) selected = null;
    final games = c.games
        .where((g) => selected == null || g.collections.contains(selected))
        .toList();
    return ResponsivePage(
      children: [
        PageHeading(
          'Collections',
          'Make room for every kind of adventure.',
          action: FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New collection'),
            onPressed: () async {
              final name = await textPrompt(context, 'New collection');
              if (name != null) await c.saveCollection(name);
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All games'),
                selected: selected == null,
                onSelected: (_) => setState(() => selected = null),
              ),
              ...c.settings.collections.map(
                (name) => ChoiceChip(
                  label: Text(name),
                  selected: selected == name,
                  onSelected: (_) => setState(() => selected = name),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (selected != null)
          AdaptiveRow(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.checklist, size: 16),
                label: const Text('Manage games'),
                onPressed: c.games.isEmpty
                    ? null
                    : () => _manageGames(selected!),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Rename'),
                onPressed: () async {
                  final old = selected!;
                  final name = await textPrompt(
                    context,
                    'Rename collection',
                    value: old,
                  );
                  if (name != null) {
                    await c.saveCollection(name, previous: old);
                    if (mounted) setState(() => selected = name);
                  }
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete collection'),
                onPressed: () async {
                  final name = selected!;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete collection?'),
                      content: Text(
                        'Delete “$name”? Your games and session history will stay in your vault.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await c.deleteCollection(name);
                },
              ),
            ],
          ),
        const SizedBox(height: 12),
        Expanded(
          child: games.isEmpty
              ? const Center(
                  child: Text(
                    'Use Manage games to add games to this collection.',
                  ),
                )
              : VaultGrid(
                  updates: c.steamUpdates,
                  games: games,
                  onOpen: widget.onOpen,
                  onFavorite: (g) =>
                      c.update(g.appId, (v) => v.copy(favorite: !v.favorite)),
                ),
        ),
      ],
    );
  }
}
