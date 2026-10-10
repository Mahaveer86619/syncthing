import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Talks to LauncherIcon.kt, which owns the festival calendar and the launcher-icon aliases.
class Festival {
  const Festival(this.id, this.greeting, this.emoji);

  final String id, greeting, emoji;

  IconData get icon => switch (id) {
        'diwali' => Icons.local_fire_department_rounded,
        'holi' => Icons.palette_rounded,
        'christmas' => Icons.park_rounded,
        'newyear' => Icons.celebration_rounded,
        _ => Icons.flag_rounded,
      };

  static const _channel = MethodChannel('syncthing/launcher_icon');

  static const iconModes = {
    'auto': ('Dynamic', 'Colourful, and changes by itself for Diwali, Holi, Christmas, '
        'New Year and national holidays'),
    'mono': ('Monochrome', 'A quiet grey icon that never changes'),
  };

  static Future<Festival?> today() async {
    final m = await _channel.invokeMapMethod<String, String>('festival');
    return m == null ? null : Festival(m['id']!, m['greeting']!, m['emoji']!);
  }

  static Future<String> iconMode() async =>
      await _channel.invokeMethod<String>('getMode') ?? 'auto';

  static Future<void> setIconMode(String mode) => _channel.invokeMethod('setMode', mode);
}
