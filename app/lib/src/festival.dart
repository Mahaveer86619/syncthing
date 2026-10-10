import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shared_settings.dart';
import 'ui/theme_choice.dart';

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
    'auto': ('Dynamic', 'Colourful; changes for festivals'),
    'mono': ('Monochrome', 'Grey; never changes'),
  };

  /// Opens the phone maker's auto-start screen; false when it fell back to the app info page.
  static Future<bool> openAutoStart() async =>
      await _channel.invokeMethod<bool>('openAutoStart') ?? false;

  /// Opens the system QR scanner; null when cancelled.
  static Future<String?> scanQr() => _channel.invokeMethod<String>('scanQr');

  static Future<Festival?> today() async {
    final m = await _channel.invokeMapMethod<String, String>('festival');
    return m == null ? null : Festival(m['id']!, m['greeting']!, m['emoji']!);
  }

  static Future<String> iconMode() async =>
      (await SharedSettings.read())['appIcon'] as String? ?? 'auto';

  /// The Android launcher reads the same settings file when it next swaps icons.
  static Future<void> setIconMode(String mode) async {
    await setIconModeShared(mode);
    ThemeChoice.onChanged?.call();
  }

  static Future<void> setIconModeShared(String mode) => SharedSettings.update({'appIcon': mode});
}
