import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'github.dart';
import 'ignore.dart';
import 'plan.dart';

/// GitHub's Git Data API rejects blobs above 100 MB.
const maxFileBytes = 95 * 1024 * 1024;

String gitBlobSha(List<int> bytes) {
  final sink = _DigestSink();
  sha1.startChunkedConversion(sink)
    ..add(utf8.encode('blob ${bytes.length}\x00'))
    ..add(bytes)
    ..close();
  return sink.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// What we remember between runs: the remote commit and file shas both sides agreed on,
/// plus a size/mtime cache so unchanged files are not re-hashed.
class SyncState {
  SyncState({this.commit, Map<String, String>? base, Map<String, List<dynamic>>? hashCache})
      : base = base ?? {},
        hashCache = hashCache ?? {};

  String? commit;
  Map<String, String> base;
  Map<String, List<dynamic>> hashCache;

  factory SyncState.fromJson(Map<String, dynamic> j) => SyncState(
        commit: j['commit'] as String?,
        base: Map<String, String>.from(j['base'] as Map),
        hashCache: Map<String, List<dynamic>>.from(j['hashCache'] as Map),
      );

  Map<String, dynamic> toJson() => {'commit': commit, 'base': base, 'hashCache': hashCache};
}

class SyncSummary {
  final received = <String>{}, sent = <String>{}, removedHere = <String>{}, removedThere = <String>{};
  final conflicts = <String>{};
  final List<String> skipped = [];

  int get downloaded => received.length;
  int get uploaded => sent.length;
  int get deletedLocal => removedHere.length;
  int get deletedRemote => removedThere.length;

  bool get isEmpty =>
      received.isEmpty && sent.isEmpty && removedHere.isEmpty && removedThere.isEmpty && conflicts.isEmpty;

  @override
  String toString() {
    if (isEmpty) return 'Up to date';
    final parts = [
      if (downloaded > 0) '$downloaded down',
      if (uploaded > 0) '$uploaded up',
      if (deletedLocal + deletedRemote > 0) '${deletedLocal + deletedRemote} deleted',
      if (conflicts.isNotEmpty) '${conflicts.length} conflict(s) kept as copies',
    ];
    return parts.join(', ');
  }
}

class SyncEngine {
  SyncEngine({
    required this.vault,
    required this.remote,
    required this.state,
    required this.deviceName,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Directory vault;
  final RemoteRepo remote;
  final SyncState state;
  final String deviceName;
  final DateTime Function() _now;

  /// Local-only check (no network): has anything in the vault changed since the last sync?
  Future<bool> hasLocalChanges() async {
    if (state.commit == null) return true;
    final ignore = IgnoreRules.fromGitignore(await _readText('.gitignore'));
    final local = await _scan(ignore, SyncSummary());
    if (local.length != state.base.length) return true;
    return local.entries.any((e) => state.base[e.key] != e.value);
  }

  Future<SyncSummary> run() async {
    final summary = SyncSummary();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (await _pass(summary)) return summary;
    }
    throw SyncException('Remote kept changing during sync; will retry next time');
  }

  /// Returns false when the push lost a race with another device.
  Future<bool> _pass(SyncSummary summary) async {
    final ignore = IgnoreRules.fromGitignore(await _readText('.gitignore'));
    final head = await remote.head();
    final remoteFiles = head.commit == state.commit
        ? Map.of(state.base)
        : ((await remote.tree(head.tree))..removeWhere((p, _) => ignore.ignores(p)));
    final local = await _scan(ignore, summary);
    final base = state.commit == null ? <String, String>{} : state.base;

    final actions = planSync(base: base, local: local, remote: remoteFiles);
    final changes = <String, String?>{};
    final message = CommitMessage(deviceName);

    await _forEachLimited(actions, (a) async {
      switch (a.kind) {
        case ActionKind.download:
          await _download(a.path, remoteFiles[a.path]!);
          summary.received.add(a.path);
        case ActionKind.deleteLocal:
          await _deleteLocal(a.path);
          summary.removedHere.add(a.path);
        case ActionKind.upload:
          changes[a.path] = await remote.createBlob(await _file(a.path).readAsBytes());
          remoteFiles.containsKey(a.path) ? message.modified(a.path) : message.added(a.path);
          summary.sent.add(a.path);
        case ActionKind.deleteRemote:
          changes[a.path] = null;
          message.deleted(a.path);
          summary.removedThere.add(a.path);
        case ActionKind.conflict:
          // Local version stays in place; the remote one is kept beside it under a new name.
          final copy = conflictPath(a.path, _now());
          await _download(copy, remoteFiles[a.path]!);
          changes[copy] = remoteFiles[a.path];
          changes[a.path] = await remote.createBlob(await _file(a.path).readAsBytes());
          message.conflict(a.path);
          summary.conflicts.add(a.path);
      }
    });

    var commit = head.commit;
    if (changes.isNotEmpty) {
      final pushed = await remote.commit(
        parent: head,
        changes: changes,
        message: message.toString(),
      );
      if (pushed == null) return false;
      commit = pushed;
    }

    final agreed = Map.of(remoteFiles);
    changes.forEach((p, sha) => sha == null ? agreed.remove(p) : agreed[p] = sha);
    state
      ..commit = commit
      ..base = agreed;
    return true;
  }

  File _file(String rel) => File('${vault.path}/$rel');

  Future<String?> _readText(String rel) async {
    final f = _file(rel);
    return await f.exists() ? f.readAsString() : null;
  }

  Future<Map<String, String>> _scan(IgnoreRules ignore, SyncSummary summary) async {
    final result = <String, String>{};
    final seen = <String>{};
    final root = vault.path.length + 1;
    await for (final e in vault.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(root).replaceAll('\\', '/');
      if (ignore.ignores(rel)) continue;
      final stat = await e.stat();
      if (stat.size > maxFileBytes) {
        summary.skipped.add(rel);
        continue;
      }
      seen.add(rel);
      final mtime = stat.modified.millisecondsSinceEpoch;
      final cached = state.hashCache[rel];
      if (cached != null && cached[0] == stat.size && cached[1] == mtime) {
        result[rel] = cached[2] as String;
        continue;
      }
      final sha = gitBlobSha(await e.readAsBytes());
      state.hashCache[rel] = [stat.size, mtime, sha];
      result[rel] = sha;
    }
    state.hashCache.removeWhere((p, _) => !seen.contains(p));
    return result;
  }

  Future<void> _download(String rel, String sha) async {
    final f = _file(rel);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(await remote.blob(sha), flush: true);
    final stat = await f.stat();
    state.hashCache[rel] = [stat.size, stat.modified.millisecondsSinceEpoch, sha];
  }

  Future<void> _deleteLocal(String rel) async {
    final f = _file(rel);
    if (await f.exists()) await f.delete();
    state.hashCache.remove(rel);
    // Obsidian shows empty folders, so prune the ones a remote delete left behind.
    var dir = f.parent;
    while (dir.path.length > vault.path.length && await dir.list().isEmpty) {
      await dir.delete();
      dir = dir.parent;
    }
  }

  static Future<void> _forEachLimited<T>(List<T> items, Future<void> Function(T) fn,
      {int concurrency = 6}) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await fn(items[next++]);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
  }
}
