class VaultGradient {
  VaultGradient(
    Iterable<int> colors, {
    this.direction = 45,
    this.intensity = .55,
  }) : colors = List.unmodifiable(colors);

  final List<int> colors;
  final double direction, intensity;

  Map<String, dynamic> toJson() => {
    'colors': colors,
    'direction': direction,
    'intensity': intensity,
  };

  static VaultGradient? fromJson(Object? value) {
    if (value is! Map) return null;
    final colors = value['colors'];
    if (colors is! List ||
        colors.length < 2 ||
        colors.length > 5 ||
        colors.any((c) => c is! int || c < 0xff000000 || c > 0xffffffff)) {
      return null;
    }
    double bounded(Object? value, double fallback, double max) =>
        value is num && value.isFinite
        ? value.clamp(0, max).toDouble()
        : fallback;
    return VaultGradient(
      colors.cast<int>(),
      direction: bounded(value['direction'], 45, 360),
      intensity: bounded(value['intensity'], .55, 1),
    );
  }
}
