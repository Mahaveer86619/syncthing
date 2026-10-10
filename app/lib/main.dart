import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'src/config.dart';
import 'src/runner.dart';
import 'src/schedule.dart';
import 'src/ui/home_page.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == watchTask) {
      // Fires for any shared-storage change (photos, downloads...), so only go online if the vault changed.
      await runSync(ifLocalChanged: true);
      if ((await SyncConfig.load()).autoSync) await armWatch();
    } else {
      await runSync();
    }
    // Failures are logged; returning false would only make WorkManager retry with backoff.
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  runApp(const SyncApp());
}

class SyncApp extends StatelessWidget {
  const SyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syncthing',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
