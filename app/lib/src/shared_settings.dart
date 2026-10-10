import 'dart:convert';
import 'dart:io';

/// App settings that follow the user across devices: `syncthing-config/settings.json` in the
/// notes repo. Android keeps its copy in app storage; Windows reads the one in its git clone.
///
/// Keys: `theme` (`dynamic` or `#RRGGBB`) and `appIcon` (`auto` or `mono`).
class SharedSettings {
  /// Set at startup to the platform's settings file.
  static late Future<File> Function() locate;

  static Future<Map<String, dynamic>> read() async {
    final f = await locate();
    if (!await f.exists()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return {};
    }
  }

  static Future<void> update(Map<String, dynamic> changes) async {
    final f = await locate();
    final merged = {...await read(), ...changes};
    await f.parent.create(recursive: true);
    await f.writeAsString('${const JsonEncoder.withIndent('  ').convert(merged)}\n');
  }
}
