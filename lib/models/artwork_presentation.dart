enum ArtworkFit { crop, contain, blurred }

/// Non-destructive slot preferences. Coordinates are normalized left/top -1,
/// centre 0, right/bottom 1; zoom only affects Crop to Fill.
class ArtworkPresentation {
  const ArtworkPresentation({
    this.mode = ArtworkFit.crop,
    this.x = 0,
    this.y = 0,
    this.zoom = 1,
  });
  final ArtworkFit mode;
  final double x, y, zoom;
  ArtworkPresentation copy({
    ArtworkFit? mode,
    double? x,
    double? y,
    double? zoom,
  }) => ArtworkPresentation(
    mode: mode ?? this.mode,
    x: x ?? this.x,
    y: y ?? this.y,
    zoom: zoom ?? this.zoom,
  );
  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'x': x,
    'y': y,
    'zoom': zoom,
  };
  factory ArtworkPresentation.fromJson(Map<String, dynamic> j) {
    double bounded(dynamic value, double fallback, double min, double max) =>
        value is num && value.isFinite
        ? value.toDouble().clamp(min, max)
        : fallback;
    return ArtworkPresentation(
      mode: switch (j['mode']) {
        'contain' => ArtworkFit.contain,
        'blurred' => ArtworkFit.blurred,
        _ => ArtworkFit.crop,
      },
      x: bounded(j['x'], 0, -1, 1),
      y: bounded(j['y'], 0, -1, 1),
      zoom: bounded(j['zoom'], 1, 1, 3),
    );
  }
}
