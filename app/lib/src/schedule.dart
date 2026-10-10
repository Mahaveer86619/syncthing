import 'package:workmanager/workmanager.dart';

const syncTaskName = 'vault-sync';

Future<void> applySchedule(int intervalMinutes) async {
  if (intervalMinutes <= 0) {
    await Workmanager().cancelByUniqueName(syncTaskName);
    return;
  }
  await Workmanager().registerPeriodicTask(
    syncTaskName,
    syncTaskName,
    frequency: Duration(minutes: intervalMinutes),
    constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
