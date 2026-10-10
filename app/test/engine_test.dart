import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncthing/src/sync/engine.dart';
import 'package:syncthing/src/sync/github.dart';

class FakeRemote implements RemoteRepo {
  final blobs = <String, List<int>>{};
  var files = <String, String>{};
  var commits = 0;
  var rejectNextCommit = false;
  String? lastMessage;

  RemoteHead get _head => RemoteHead('c$commits', 't$commits');

  void put(String path, String text) {
    final bytes = utf8.encode(text);
    final sha = gitBlobSha(bytes);
    blobs[sha] = bytes;
    files = {...files, path: sha};
    commits++;
  }

  void remove(String path) {
    files = {...files}..remove(path);
    commits++;
  }

  String? read(String path) => files[path] == null ? null : utf8.decode(blobs[files[path]]!);

  @override
  Future<RemoteHead> head() async => _head;

  @override
  Future<Map<String, String>> tree(String treeSha) async => Map.of(files);

  @override
  Future<List<int>> blob(String sha) async => blobs[sha]!;

  @override
  Future<String> createBlob(List<int> bytes) async {
    final sha = gitBlobSha(bytes);
    blobs[sha] = bytes;
    return sha;
  }

  @override
  Future<String?> commit({
    required RemoteHead parent,
    required Map<String, String?> changes,
    required String message,
  }) async {
    if (rejectNextCommit) {
      rejectNextCommit = false;
      put('race.md', 'pushed by someone else');
      return null;
    }
    if (parent.commit != _head.commit) return null;
    lastMessage = message;
    final next = Map.of(files);
    changes.forEach((p, sha) => sha == null ? next.remove(p) : next[p] = sha);
    files = next;
    commits++;
    return _head.commit;
  }
}

void main() {
  late Directory vault;
  late FakeRemote remote;
  late SyncState state;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('vault');
    remote = FakeRemote();
    state = SyncState();
  });

  tearDown(() => vault.delete(recursive: true));

  File f(String rel) => File('${vault.path}/$rel');
  Future<void> write(String rel, String text) async {
    await f(rel).parent.create(recursive: true);
    await f(rel).writeAsString(text);
  }

  Future<SyncSummary> sync() => SyncEngine(
        vault: vault,
        remote: remote,
        state: state,
        deviceName: 'test',
        clock: () => DateTime(2026, 1, 2, 3, 4, 5),
      ).run();

  SyncEngine engine() => SyncEngine(vault: vault, remote: remote, state: state, deviceName: 'test');

  test('local change check needs no network and spots edits, adds and deletes', () async {
    remote.put('a.md', '1');
    await sync();
    expect(await engine().hasLocalChanges(), isFalse);
    await write('.obsidian/workspace.json', 'ignored');
    expect(await engine().hasLocalChanges(), isFalse);
    await write('new.md', 'x');
    expect(await engine().hasLocalChanges(), isTrue);
    await sync();
    await f('a.md').delete();
    expect(await engine().hasLocalChanges(), isTrue);
  });

  test('commit message names device and changes', () async {
    remote.put('old.md', '1');
    await sync();
    await write('new.md', 'x');
    await write('old.md', '2');
    await sync();
    expect(remote.lastMessage, 'test: 1 added, 1 modified\n\nA new.md\nM old.md');
  });

  test('first sync merges both sides', () async {
    remote.put('from-laptop.md', 'L');
    await write('from-phone.md', 'P');
    final s = await sync();
    expect((s.downloaded, s.uploaded), (1, 1));
    expect(await f('from-laptop.md').readAsString(), 'L');
    expect(remote.read('from-phone.md'), 'P');
    expect((await sync()).isEmpty, isTrue);
  });

  test('edits, deletes and empty folder cleanup flow both ways', () async {
    remote.put('a.md', '1');
    remote.put('dir/b.md', '1');
    await sync();

    await write('a.md', 'phone edit');
    remote.remove('dir/b.md');
    final s = await sync();
    expect((s.uploaded, s.deletedLocal), (1, 1));
    expect(remote.read('a.md'), 'phone edit');
    expect(await Directory('${vault.path}/dir').exists(), isFalse);

    await f('a.md').delete();
    await sync();
    expect(remote.read('a.md'), isNull);
  });

  test('conflicting edits keep both versions everywhere', () async {
    remote.put('n.md', 'base');
    await sync();
    remote.put('n.md', 'laptop');
    await write('n.md', 'phone');

    expect((await sync()).conflicts, 1);
    const copy = 'n (conflict 2026-01-02 030405).md';
    expect(await f('n.md').readAsString(), 'phone');
    expect(await f(copy).readAsString(), 'laptop');
    expect(remote.read('n.md'), 'phone');
    expect(remote.read(copy), 'laptop');
  });

  test('ignored files are never synced', () async {
    await write('.obsidian/workspace.json', '{}');
    await write('.obsidian/app.json', '{}');
    await sync();
    expect(remote.files.keys, ['.obsidian/app.json']);
  });

  test('a lost push race is retried on top of the new remote', () async {
    await write('mine.md', 'x');
    remote.rejectNextCommit = true;
    await sync();
    expect(remote.read('mine.md'), 'x');
    expect(await f('race.md').readAsString(), 'pushed by someone else');
  });
}
