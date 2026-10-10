import 'package:workmanager/workmanager.dart';

/// Pulls remote changes and is the guaranteed floor; Android won't run periodic work more often.
const pollTask = 'vault-poll';

/// Fires when anything in shared storage changes (MediaStore), i.e. right after Obsidian saves.
/// One-shot by design, so it is re-armed after every run.
const watchTask = 'vault-watch';

const _filesUri = 'content://media/external/file';

Future<void> applySchedule(bool autoSync) async {
  if (!autoSync) {
    await Workmanager().cancelByUniqueName(pollTask);
    await Workmanager().cancelByUniqueName(watchTask);
    return;
  }
  await Workmanager().registerPeriodicTask(
    pollTask,
    pollTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
  await armWatch();
}

Future<void> armWatch() => Workmanager().registerOneOffTask(
      watchTask,
      watchTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
        contentUriTriggers: [ContentUriTrigger(uri: _filesUri, triggerForDescendants: true)],
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
