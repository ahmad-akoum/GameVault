import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'components.dart';
import 'responsive.dart';

class ArtworkViewer extends StatefulWidget {
  const ArtworkViewer({super.key, required this.title, this.path});
  final String title;
  final String? path;
  @override
  State<ArtworkViewer> createState() => _ArtworkViewerState();
}

class _ArtworkViewerState extends State<ArtworkViewer> {
  final transform = TransformationController();
  Size viewport = Size.zero;
  void zoom(double factor) {
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      5.0,
    );
    transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        viewport.width * (1 - scale) / 2,
        viewport.height * (1 - scale) / 2,
        0,
      );
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    },
    child: Focus(
      autofocus: true,
      child: Dialog.fullscreen(
        child: Column(
          children: [
            Material(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AdaptiveRow(
                    breakpoint: 480,
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Zoom out',
                            onPressed: () => zoom(1 / 1.25),
                            icon: const Icon(Icons.zoom_out),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            onPressed: () => zoom(1.25),
                            icon: const Icon(Icons.zoom_in),
                          ),
                          IconButton(
                            tooltip: 'Reset zoom',
                            onPressed: () =>
                                transform.value = Matrix4.identity(),
                            icon: const Icon(Icons.fit_screen),
                          ),
                          IconButton(
                            tooltip: 'Close artwork',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  viewport = constraints.biggest;
                  return ClipRect(
                    child: InteractiveViewer(
                      transformationController: transform,
                      minScale: 1,
                      maxScale: 5,
                      child: SizedBox.expand(
                        child: GameArtwork(
                          path: widget.path,
                          title: 'Artwork unavailable',
                          fit: BoxFit.contain,
                          fullResolution: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Scroll to zoom • Drag to pan • Esc to close • Image quality depends on the original artwork',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
