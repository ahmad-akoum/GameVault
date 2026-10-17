import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/artwork_store.dart';
import '../models/game.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'artwork_viewer.dart';

class ArtworkManager extends StatefulWidget {
  const ArtworkManager({super.key, required this.controller, required this.id});
  final VaultController controller;
  final int id;
  @override
  State<ArtworkManager> createState() => _ArtworkManagerState();
}

class _ArtworkManagerState extends State<ArtworkManager> {
  bool cover = true, contained = false, busy = false;
  String? draft, message;
  final additions = <bool, List<String>>{true: [], false: []};
  late final store = ArtworkStore(widget.controller.store.artwork);
  VaultGame get game => widget.controller.game(widget.id)!;
  String? get selected => cover ? game.coverPath : game.profileArtworkPath;
  String? get original => game.artwork == null
      ? selected
      : cover
      ? game.artwork!.originalCover
      : game.artwork!.originalHero;
  List<String> get choices => {
    ?selected,
    ?original,
    ...?(cover ? game.artwork?.covers : game.artwork?.heroes),
    ...additions[cover]!,
  }.toList();
  String label(String path) {
    if (path == original) return 'Original / Default';
    final name = p.basename(path);
    if (name.contains('_steam_library_600x900')) return 'Steam library cover';
    if (name.contains('_steam_library_hero')) return 'Steam library banner';
    if (name.contains('_steam_header')) return 'Steam header';
    return 'Saved artwork';
  }

  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    draft = selected;
    contained =
        (cover ? game.artwork?.coverContained : game.artwork?.heroContained) ??
        false;
    message = null;
  }

  Future<void> work(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on ArtworkFailure catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Artwork could not be saved or loaded. Check the file and folder permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    await work(() async {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Still images',
            extensions: ArtworkStore.extensions,
          ),
        ],
      );
      if (file == null || !mounted) return;
      final path = await store.importImage(file.path, widget.id, cover);
      if (mounted) {
        setState(() {
          additions[cover]!.add(path);
          draft = path;
          message = 'Preview ready. Apply to use this image.';
        });
      }
    });
  }

  Future<void> apply() => work(() async {
    if (draft != null) await store.validate(draft!);
    final saved = await widget.controller.applyArtwork(
      widget.id,
      cover: cover,
      path: draft,
      contained: contained,
      choices: choices,
    );
    if (mounted) {
      setState(
        () => message = saved
            ? '${cover ? 'Cover' : 'Banner'} applied.'
            : 'Artwork was not saved. Your previous selection is preserved.',
      );
    }
  });
  Future<void> checkSteam() => work(() async {
    final paths = await store.steamChoices(widget.id, cover, choices);
    if (mounted) {
      setState(() {
        additions[cover]!.addAll(paths);
        message = paths.isEmpty
            ? 'No additional usable Steam artwork was returned. Existing choices are preserved.'
            : 'Steam choices are ready to preview. Nothing has been applied.';
      });
    }
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget current(bool isCover) => SizedBox(
      width: isCover
          ? 100
          : (MediaQuery.sizeOf(context).width - 64).clamp(100, 250),
      child: Column(
        children: [
          Text(
            isCover ? 'Current cover' : 'Current banner',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: isCover ? 150 : 80,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: GameArtwork(
                  path: isCover ? game.coverPath : game.profileArtworkPath,
                  title: 'No artwork',
                  fit:
                      (isCover
                              ? game.artwork?.coverContained
                              : game.artwork?.heroContained) ==
                          true
                      ? BoxFit.contain
                      : BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: SizedBox(
          width: 850,
          height: MediaQuery.sizeOf(context).height * .88,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manage Artwork',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close artwork manager',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          game.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          children: [current(true), current(false)],
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final isCover in [true, false])
                              ChoiceChip(
                                label: Text(
                                  isCover ? 'Library cover' : 'Profile banner',
                                ),
                                selected: cover == isCover,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() {
                                        cover = isCover;
                                        reset();
                                      }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: cover ? 280 : 210,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: cover ? 2 / 3 : 1920 / 620,
                              child: ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: GameArtwork(
                                  path: draft,
                                  title: 'No artwork selected',
                                  fit: contained
                                      ? BoxFit.contain
                                      : BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceChip(
                              label: const Text('Crop to fill'),
                              selected: !contained,
                              onSelected: busy
                                  ? null
                                  : (_) => setState(() => contained = false),
                            ),
                            ChoiceChip(
                              label: const Text('Fit entire image'),
                              selected: contained,
                              onSelected: busy
                                  ? null
                                  : (_) => setState(() => contained = true),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.fullscreen),
                              label: const Text('Enlarge preview'),
                              onPressed: busy
                                  ? null
                                  : () => showDialog<void>(
                                      context: context,
                                      builder: (_) => ArtworkViewer(
                                        title: 'Artwork preview',
                                        path: draft,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Choose an image to preview',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final path in choices)
                              SizedBox(
                                width: 130,
                                child: InkWell(
                                  onTap: busy
                                      ? null
                                      : () => setState(() {
                                          draft = path;
                                          message = null;
                                        }),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: path == draft
                                            ? scheme.primary
                                            : scheme.outlineVariant,
                                        width: path == draft ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: cover ? 130 : 70,
                                          width: double.infinity,
                                          child: GameArtwork(
                                            path: path,
                                            title: 'Unavailable',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(label(path), maxLines: 1),
                                        if (path == selected)
                                          const Text(
                                            'Currently selected',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        if (path == draft)
                                          const Icon(
                                            Icons.check_circle,
                                            size: 18,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy ? null : import,
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Import image'),
                            ),
                            if (!game.isManual)
                              OutlinedButton.icon(
                                onPressed: busy ? null : checkSteam,
                                icon: const Icon(Icons.cloud_download_outlined),
                                label: const Text('Check Steam artwork'),
                              ),
                            TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      draft = original;
                                      contained = false;
                                      message =
                                          'Default preview ready. Apply to restore only this artwork.';
                                    }),
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore Default'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Cover and banner are independent. Steam may provide only one image or none; no historical or promotional variants are assumed. Import only images you have permission to use.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      message!,
                      key: const ValueKey('artworkMessage'),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : apply,
                      child: Text('Apply ${cover ? 'cover' : 'banner'}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
