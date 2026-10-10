import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'activity.dart';
import 'config.dart';
import 'sync/engine.dart';
import 'sync/github.dart';
import 'vaults.dart';

const _maxActivities = 100;

/// Runs one sync with the saved config. Shared by the UI and the background worker,
/// which run in separate isolates, so a lock file keeps them from overlapping.
/// With [ifLocalChanged], nothing is fetched unless the vault differs from the last sync.
/// Returns what was recorded in the activity feed, or null when nothing worth showing happened.
Future<Activity?> runSync({bool ifLocalChanged = false}) async {
  final dir = await getApplicationSupportDirectory();
  final lock = File('${dir.path}/sync.lock');
  try {
    await lock.create(exclusive: true);
  } on FileSystemException {
    final age = DateTime.now().difference((await lock.stat()).modified);
    if (age < const Duration(minutes: 10)) return null;
    // A lock this old belongs to a run the OS killed.
    await lock.delete();
    await lock.create(exclusive: true);
  }

  try {
    final config = await SyncConfig.load();
    if (!config.isComplete) throw SyncException('Finish the settings first');
    final vault = Directory(config.vaultPath);
    if (!await vault.exists()) throw SyncException('Vault folder not found: ${config.vaultPath}');
    // Syncing a parent folder would upload every vault under a subfolder; refuse instead.
    if (!isVault(vault.path)) {
      throw SyncException('Not an Obsidian vault (no .obsidian folder): pick the vault in Settings');
    }

    final stateFile = File('${dir.path}/state.json');
    final state = await _loadState(stateFile, config.stateKey);
    final engine = SyncEngine(
      vault: vault,
      remote: GitHubRepo(
        owner: config.owner,
        repo: config.repoName,
        branch: config.branch,
        token: config.token,
      ),
      state: state,
      deviceName: config.deviceName,
    );
    if (ifLocalChanged && !await engine.hasLocalChanges()) {
      await _saveState(stateFile, config.stateKey, state);
      return null;
    }
    final summary = await engine.run();
    await _saveState(stateFile, config.stateKey, state);
    await File('${dir.path}/last_check').writeAsString(DateTime.now().toIso8601String());
    if (summary.isEmpty) return null;
    final activity = Activity.fromSummary(summary);
    await _record(activity);
    return activity;
  } catch (e) {
    final activity = Activity.failure(e);
    await _record(activity);
    return activity;
  } finally {
    await lock.delete();
  }
}

Future<void> _saveState(File f, String key, SyncState state) =>
    f.writeAsString(jsonEncode({'key': key, ...state.toJson()}));

Future<SyncState> _loadState(File f, String key) async {
  if (!await f.exists()) return SyncState();
  final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  return j['key'] == key ? SyncState.fromJson(j) : SyncState();
}

Future<File> _file(String name) async =>
    File('${(await getApplicationSupportDirectory()).path}/$name');

Future<void> _record(Activity a) async {
  final all = await readActivity();
  // A failure that keeps repeating (e.g. offline for hours) stays one entry with a fresh time.
  if (a.kind != ActivityKind.synced &&
      all.isNotEmpty &&
      all.first.kind == a.kind &&
      all.first.message == a.message) {
    all.removeAt(0);
  }
  all.insert(0, a);
  final lines = all.take(_maxActivities).toList().reversed.map((e) => jsonEncode(e.toJson()));
  await (await _file('activity.jsonl')).writeAsString('${lines.join('\n')}\n');
}

/// Newest first.
Future<List<Activity>> readActivity() async {
  final f = await _file('activity.jsonl');
  if (!await f.exists()) return [];
  final out = <Activity>[];
  for (final line in await f.readAsLines()) {
    if (line.isEmpty) continue;
    try {
      out.add(Activity.fromJson(jsonDecode(line) as Map<String, dynamic>));
    } on FormatException {
      continue;
    }
  }
  return out.reversed.toList();
}

Future<DateTime?> lastCheck() async {
  final f = await _file('last_check');
  return await f.exists() ? DateTime.tryParse(await f.readAsString()) : null;
}

/// Notes (`.md` files) both sides agreed on at the last sync.
Future<int> syncedNoteCount() async {
  final f = await _file('state.json');
  if (!await f.exists()) return 0;
  final base = (jsonDecode(await f.readAsString()) as Map<String, dynamic>)['base'] as Map?;
  return base?.keys.where((k) => (k as String).endsWith('.md')).length ?? 0;
}

/// Background checks every 15 min; Android picks the exact moment, so this is an estimate.
const pollInterval = Duration(minutes: 15);

Future<void> markPoll() async =>
    (await _file('last_poll')).writeAsString(DateTime.now().toIso8601String());

/// Remembers when auto sync was switched on, so there is a countdown before the first poll runs.
Future<void> markPollScheduled() async {
  final f = await _file('last_poll');
  if (!await f.exists()) await markPoll();
}

Future<DateTime?> nextPoll() async {
  final f = await _file('last_poll');
  if (!await f.exists()) return null;
  final last = DateTime.tryParse(await f.readAsString());
  return last?.add(pollInterval);
}
