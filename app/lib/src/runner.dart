import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'sync/engine.dart';
import 'sync/github.dart';

const _maxLogLines = 200;

/// Runs one sync with the saved config. Shared by the UI and the background worker,
/// which run in separate isolates, so a lock file keeps them from overlapping.
Future<String> runSync() async {
  final dir = await getApplicationSupportDirectory();
  final lock = File('${dir.path}/sync.lock');
  try {
    await lock.create(exclusive: true);
  } on FileSystemException {
    final age = DateTime.now().difference((await lock.stat()).modified);
    if (age < const Duration(minutes: 10)) return 'Another sync is already running';
    // A lock this old belongs to a run the OS killed.
    await lock.delete();
    await lock.create(exclusive: true);
  }

  try {
    final config = await SyncConfig.load();
    if (!config.isComplete) throw SyncException('Finish the settings first');
    final vault = Directory(config.vaultPath);
    if (!await vault.exists()) throw SyncException('Vault folder not found: ${config.vaultPath}');

    final stateFile = File('${dir.path}/state.json');
    final state = await _loadState(stateFile, config.stateKey);
    final summary = await SyncEngine(
      vault: vault,
      remote: GitHubRepo(
        owner: config.owner,
        repo: config.repoName,
        branch: config.branch,
        token: config.token,
      ),
      state: state,
      deviceName: config.deviceName,
    ).run();
    await stateFile.writeAsString(jsonEncode({'key': config.stateKey, ...state.toJson()}));

    var msg = summary.toString();
    if (summary.skipped.isNotEmpty) msg += ' (skipped ${summary.skipped.length} file(s) over 95 MB)';
    await appendLog(msg);
    return msg;
  } catch (e) {
    final msg = e is SocketException ? 'Offline; will retry later' : 'Error: $e';
    await appendLog(msg);
    return msg;
  } finally {
    await lock.delete();
  }
}

Future<SyncState> _loadState(File f, String key) async {
  if (!await f.exists()) return SyncState();
  final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  return j['key'] == key ? SyncState.fromJson(j) : SyncState();
}

Future<File> _logFile() async => File('${(await getApplicationSupportDirectory()).path}/sync.log');

Future<void> appendLog(String message) async {
  final f = await _logFile();
  final lines = await f.exists() ? await f.readAsLines() : <String>[];
  lines.add('${DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ')}  $message');
  final keep = lines.length > _maxLogLines ? lines.sublist(lines.length - _maxLogLines) : lines;
  await f.writeAsString('${keep.join('\n')}\n');
}

Future<List<String>> readLog() async {
  final f = await _logFile();
  return await f.exists() ? (await f.readAsLines()).reversed.toList() : [];
}
