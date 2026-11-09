import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/vault_gradient.dart';
import 'theme.dart';

class ThemeEditor extends StatefulWidget {
  const ThemeEditor({super.key, required this.settings, this.initialRole = 0});
  final VaultSettings settings;
  final int initialRole;

  @override
  State<ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<ThemeEditor> {
  static const quick = [
    0xffb8d96e,
    0xff78aaff,
    0xffbf9aff,
    0xffff7e90,
    0xff6ed8ae,
    0xff83cddd,
    0xffffc65c,
    0xff798397,
  ];
  late VaultSettings draft = widget.settings;
  late int role = widget.initialRole;
  int stop = 0;
  late final hex = TextEditingController();
  late HSVColor hsv;
  bool valid = true;

  @override
  void initState() {
    super.initState();
    select(role);
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void select(int next) {
    role = next;
    final color = switch (role) {
      0 => draft.accent,
      1 => draft.background ?? 0xff101520,
      2 => draft.surface ?? 0xff182130,
      _ => draft.gradient!.colors[stop],
    };
    hsv = HSVColor.fromColor(Color(color));
    syncHex(color);
  }

  void syncHex(int color) {
    hex.text = color
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    valid = true;
  }

  void change(HSVColor value, {bool sync = true}) {
    hsv = value;
    final color = value.toColor().toARGB32();
    if (sync) syncHex(color);
    switch (role) {
      case 0:
        draft = draft.copy(accent: color);
      case 1:
        draft = draft.copy(background: color);
      case 2:
        draft = draft.copy(surface: color);
      default:
        final colors = [...draft.gradient!.colors]..[stop] = color;
        gradient(colors);
    }
  }

  void gradient(List<int> colors, {double? direction, double? intensity}) {
    draft = draft.copy(
      gradient: VaultGradient(
        colors,
        direction: direction ?? draft.gradient?.direction ?? 45,
        intensity: intensity ?? draft.gradient?.intensity ?? .55,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = switch (draft.theme) {
      AppearanceMode.dark => Brightness.dark,
      AppearanceMode.light => Brightness.light,
      AppearanceMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final preview = vaultTheme(
      brightness,
      draft.accent,
      background: draft.background,
      surface: draft.surface,
    );
    final stops = draft.gradient?.colors;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Theme studio'),
          const SizedBox(height: 12),
          Theme(
            data: preview,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: preview.colorScheme.surface,
                gradient: vaultBackdrop(preview, draft.gradient),
                border: Border.all(color: preview.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                tileColor: preview.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                leading: Icon(
                  Icons.videogame_asset_outlined,
                  color: preview.colorScheme.primary,
                ),
                title: const Text('Your next adventure'),
                subtitle: const Text('Live theme preview'),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in AppearanceMode.values)
                    ChoiceChip(
                      label: Text(switch (mode) {
                        AppearanceMode.dark => 'Dark',
                        AppearanceMode.light => 'Light',
                        AppearanceMode.system => 'System',
                      }),
                      selected: mode == draft.theme,
                      onSelected: (_) =>
                          setState(() => draft = draft.copy(theme: mode)),
                    ),
                ],
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gradient backdrop'),
                value: stops != null,
                onChanged: (enabled) => setState(() {
                  if (enabled) {
                    gradient([draft.accent, draft.surface ?? 0xff647ca8]);
                    stop = 0;
                    select(3);
                  } else {
                    draft = draft.copy(clearGradient: true);
                    select(0);
                  }
                }),
              ),
              if (stops != null) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (i, color) in stops.indexed)
                      ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: Color(color)),
                        label: Text('Stop ${i + 1}'),
                        selected: role == 3 && i == stop,
                        onSelected: (_) => setState(() {
                          stop = i;
                          select(3);
                        }),
                      ),
                    if (stops.length < 5)
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add color'),
                        onPressed: () => setState(() {
                          gradient([...stops, draft.accent]);
                          stop = stops.length;
                          select(3);
                        }),
                      ),
                    if (stops.length > 2 && role == 3)
                      TextButton.icon(
                        icon: const Icon(Icons.remove),
                        label: const Text('Remove stop'),
                        onPressed: () => setState(() {
                          gradient([...stops]..removeAt(stop));
                          stop = stop.clamp(0, stops.length - 2);
                          select(3);
                        }),
                      ),
                  ],
                ),
                if (role == 3)
                  const Text(
                    'Edit the selected stop using the color controls below.',
                  ),
                slider(
                  'Direction',
                  draft.gradient!.direction,
                  360,
                  (v) => gradient(stops, direction: v),
                  suffix: '°',
                ),
                slider(
                  'Intensity',
                  draft.gradient!.intensity * 100,
                  100,
                  (v) => gradient(stops, intensity: v / 100),
                  suffix: '%',
                ),
              ],
              const Divider(height: 28),
              Wrap(
                spacing: 8,
                children: [
                  for (final (index, name) in [
                    'Accent',
                    'Background',
                    'Surface',
                  ].indexed)
                    ChoiceChip(
                      label: Text(name),
                      selected: role == index,
                      onSelected: (_) => setState(() => select(index)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Quick colors'),
              Wrap(
                children: [
                  for (final color in quick)
                    IconButton(
                      tooltip:
                          '#${color.toRadixString(16).substring(2).toUpperCase()}',
                      onPressed: () => setState(
                        () => change(HSVColor.fromColor(Color(color))),
                      ),
                      icon: Icon(Icons.circle, color: Color(color)),
                    ),
                ],
              ),
              TextField(
                controller: hex,
                decoration: InputDecoration(
                  labelText: 'Hex color',
                  prefixText: '#',
                  errorText: valid ? null : 'Enter six hexadecimal digits',
                ),
                onChanged: (text) => setState(() {
                  final raw = text.trim().replaceFirst(RegExp(r'^#'), '');
                  valid = RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(raw);
                  if (valid) {
                    change(
                      HSVColor.fromColor(
                        Color(0xff000000 | int.parse(raw, radix: 16)),
                      ),
                      sync: false,
                    );
                  }
                }),
              ),
              const SizedBox(height: 12),
              const Text('Saturation and brightness'),
              SizedBox(
                height: 104,
                child: LayoutBuilder(
                  builder: (_, box) {
                    void pick(Offset offset) => setState(
                      () => change(
                        hsv
                            .withSaturation(
                              (offset.dx / box.maxWidth).clamp(0, 1),
                            )
                            .withValue(
                              (1 - offset.dy / box.maxHeight).clamp(0, 1),
                            ),
                      ),
                    );
                    return GestureDetector(
                      onTapDown: (d) => pick(d.localPosition),
                      onPanStart: (d) => pick(d.localPosition),
                      onPanUpdate: (d) => pick(d.localPosition),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white,
                                    hsv
                                        .withSaturation(1)
                                        .withValue(1)
                                        .toColor(),
                                  ],
                                ),
                              ),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black],
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment(
                                hsv.saturation * 2 - 1,
                                1 - hsv.value * 2,
                              ),
                              child: const Icon(
                                Icons.radio_button_unchecked,
                                color: Colors.white,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              slider(
                'Hue',
                hsv.hue,
                360,
                (v) => change(hsv.withHue(v)),
                track: const LinearGradient(
                  colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Color(0xffff00ff),
                    Colors.red,
                  ],
                ),
              ),
              slider(
                'Saturation',
                hsv.saturation * 100,
                100,
                (v) => change(hsv.withSaturation(v / 100)),
                suffix: '%',
              ),
              slider(
                'Shade',
                hsv.value * 100,
                100,
                (v) => change(hsv.withValue(v / 100)),
                suffix: '%',
              ),
              Wrap(
                spacing: 6,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('Surprise me'),
                    onPressed: () => setState(() {
                      final random = Random();
                      final hue = random.nextDouble() * 360;
                      int tone(double shift, double shade) => HSVColor.fromAHSV(
                        1,
                        (hue + shift) % 360,
                        .65,
                        shade,
                      ).toColor().toARGB32();
                      draft = draft.copy(
                        accent: tone(0, .92),
                        background: tone(30, .16),
                        surface: tone(60, .24),
                      );
                      gradient([
                        tone(0, .8),
                        tone(65, .8),
                      ], direction: random.nextDouble() * 360);
                      select(0);
                    }),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      draft = draft.copy(
                        resetColors: true,
                        accent: const VaultSettings().accent,
                        theme: const VaultSettings().theme,
                      );
                      select(0);
                    }),
                    child: const Text('Reset defaults'),
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
          onPressed: valid ? () => Navigator.pop(context, draft) : null,
          child: const Text('Apply theme'),
        ),
      ],
    );
  }

  Widget slider(
    String title,
    double value,
    double max,
    ValueChanged<double> change, {
    String suffix = '°',
    Gradient? track,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title · ${value.round()}$suffix'),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: track,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Slider(
          value: value,
          max: max,
          divisions: max.round(),
          activeColor: track == null ? null : Colors.transparent,
          inactiveColor: track == null ? null : Colors.transparent,
          thumbColor: track == null
              ? null
              : Theme.of(context).colorScheme.onSurface,
          semanticFormatterCallback: (v) => '$title ${v.round()}$suffix',
          onChanged: (v) => setState(() => change(v)),
        ),
      ),
    ],
  );
}
