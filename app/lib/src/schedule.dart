import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import 'runner.dart';

/// Pulls remote changes and is the guaranteed floor; Android won't run periodic work more often.
const pollTask = 'vault-poll';

/// Fires when anything in shared storage changes (MediaStore), i.e. right after Obsidian saves.
/// One-shot by design, so it is re-armed after every run.
const watchTask = 'vault-watch';

const _filesUri = 'content://media/external/file';

const _native = MethodChannel('syncthing/launcher_icon');

/// Some phone makers' battery managers (Infinix XOS, MIUI...) delete an app's scheduled jobs on
/// swipe-away or when its launcher icon changes. Rebuilds the schedule if that happened and
/// returns true so the user can be told.
Future<bool> ensureSchedule() async {
  final pending = await _native.invokeMethod<int>('pendingJobs') ?? 0;
  // Poll + edit watch + launcher-icon check; fewer means some were deleted.
  if (pending >= 3) return false;
  await Workmanager().cancelByUniqueName(pollTask);
  await Workmanager().cancelByUniqueName(watchTask);
  await applySchedule(true);
  return true;
}

Future<void> applySchedule(bool autoSync) async {
  if (!autoSync) {
    await Workmanager().cancelByUniqueName(pollTask);
    await Workmanager().cancelByUniqueName(watchTask);
    return;
  }
  await Workmanager().registerPeriodicTask(
    pollTask,
    pollTask,
    frequency: pollInterval,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
  await markPollScheduled();
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
