import 'package:flutter/material.dart';

import '../shared_settings.dart';

import 'widgets.dart';

/// The user's accent: null follows the system (wallpaper on Android, accent colour on Windows).
class ThemeChoice {
  static final seed = ValueNotifier<Color?>(null);

  static const presets = <String, Color>{
    'Violet': Color(0xFF6750A4),
    'Ocean': Color(0xFF0061A4),
    'Teal': Color(0xFF006A6A),
    'Forest': Color(0xFF386A20),
    'Marigold': Color(0xFF8B6100),
    'Coral': Color(0xFFB4462E),
    'Rose': Color(0xFFA23E6C),
  };

  /// Called after every sync too, so a theme picked on the other device shows up here.
  static Future<void> load() async {
    final v = (await SharedSettings.read())['theme'] as String?;
    final hex = v == null || v == 'dynamic' ? null : int.tryParse(v.replaceFirst('#', ''), radix: 16);
    final color = hex == null ? null : Color(0xFF000000 | hex);
    if (seed.value?.toARGB32() != color?.toARGB32()) seed.value = color;
  }

  static Future<void> set(Color? color) async {
    seed.value = color;
    final hex = color?.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    await SharedSettings.update({'theme': hex == null ? 'dynamic' : '#$hex'});
    onChanged?.call();
  }

  /// Pushes the change to the repo (the phone has no file watcher on app storage).
  static void Function()? onChanged;
}

/// "Dynamic" plus the preset swatches; tapping one recolours the app immediately.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Color?>(
      valueListenable: ThemeChoice.seed,
      builder: (context, current, _) => Section(
        title: 'THEME',
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        children: [
          Text(
            current == null
                ? 'Dynamic: matches your wallpaper or system accent colour'
                : ThemeChoice.presets.entries.firstWhere((e) => e.value == current,
                    orElse: () => const MapEntry('Custom', Colors.transparent)).key,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Swatch(
                selected: current == null,
                label: 'Dynamic',
                onTap: () => ThemeChoice.set(null),
                color: theme.colorScheme.primaryContainer,
                child: Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.onPrimaryContainer),
              ),
              for (final e in ThemeChoice.presets.entries)
                _Swatch(
                  selected: current == e.value,
                  label: e.key,
                  color: ColorScheme.fromSeed(seedColor: e.value, brightness: theme.brightness)
                      .primary,
                  onTap: () => ThemeChoice.set(e.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.selected,
    required this.label,
    required this.color,
    required this.onTap,
    this.child,
  });

  final bool selected;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label theme',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            width: 52,
            height: 52,
            padding: EdgeInsets.all(selected ? 4 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(
                child: selected && child == null
                    ? Icon(Icons.check_rounded,
                        color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                            ? Colors.white
                            : Colors.black)
                    : child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
