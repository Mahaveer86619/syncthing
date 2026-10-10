import 'dart:convert';

import 'package:http/http.dart' as http;

class SyncException implements Exception {
  SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteHead {
  const RemoteHead(this.commit, this.tree);

  final String commit;
  final String tree;
}

/// What the sync engine needs from the remote; GitHub in production, in-memory in tests.
abstract class RemoteRepo {
  Future<RemoteHead> head();

  /// path -> blob sha for every regular file in the tree.
  Future<Map<String, String>> tree(String treeSha);

  Future<List<int>> blob(String sha);

  Future<String> createBlob(List<int> bytes);

  /// Applies [changes] (path -> blob sha, or null to delete) on top of [parent] and
  /// fast-forwards the branch. Returns the new commit sha, or null if the branch moved.
  Future<String?> commit({
    required RemoteHead parent,
    required Map<String, String?> changes,
    required String message,
  });
}

class GitHubRepo implements RemoteRepo {
  GitHubRepo({
    required this.owner,
    required this.repo,
    required this.branch,
    required String token,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _headers = {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        };

  final String owner, repo, branch;
  final http.Client _client;
  final Map<String, String> _headers;

  Uri _uri(String path) => Uri.https('api.github.com', '/repos/$owner/$repo$path');

  Future<http.Response> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, _uri(path))..headers.addAll(_headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    return http.Response.fromStream(await _client.send(req));
  }

  Map<String, dynamic> _json(http.Response res, String what) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 401) throw SyncException('GitHub rejected the token (401)');
    if (res.statusCode == 404) {
      throw SyncException('$what: not found (check repo name and token access)');
    }
    throw SyncException('$what failed: HTTP ${res.statusCode} ${res.body}');
  }

  @override
  Future<RemoteHead> head() async {
    final ref = await _send('GET', '/git/ref/heads/$branch');
    // 409 means the repository has no commits at all.
    if (ref.statusCode == 409) {
      throw SyncException('Notes repo is empty: push from the laptop first, '
          'or create it with a README');
    }
    if (ref.statusCode == 404) {
      _json(await _send('GET', ''), 'Repository');
      throw SyncException('Branch "$branch" does not exist in $owner/$repo');
    }
    final commitSha = _json(ref, 'Branch')['object']['sha'] as String;
    final commit = _json(await _send('GET', '/git/commits/$commitSha'), 'Commit');
    return RemoteHead(commitSha, commit['tree']['sha'] as String);
  }

  @override
  Future<Map<String, String>> tree(String treeSha) async {
    final res = _json(await _send('GET', '/git/trees/$treeSha?recursive=1'), 'Tree');
    if (res['truncated'] == true) {
      throw SyncException('Repository tree too large for the GitHub API');
    }
    return {
      for (final e in res['tree'] as List)
        if (e['type'] == 'blob' && e['mode'] != '120000') e['path'] as String: e['sha'] as String,
    };
  }

  @override
  Future<List<int>> blob(String sha) async {
    final res = _json(await _send('GET', '/git/blobs/$sha'), 'Blob');
    return base64.decode((res['content'] as String).replaceAll('\n', ''));
  }

  @override
  Future<String> createBlob(List<int> bytes) async {
    final res = _json(
      await _send('POST', '/git/blobs', {'content': base64.encode(bytes), 'encoding': 'base64'}),
      'Upload',
    );
    return res['sha'] as String;
  }

  @override
  Future<String?> commit({
    required RemoteHead parent,
    required Map<String, String?> changes,
    required String message,
  }) async {
    final tree = _json(
      await _send('POST', '/git/trees', {
        'base_tree': parent.tree,
        'tree': [
          for (final e in changes.entries)
            {'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': e.value},
        ],
      }),
      'Tree update',
    );
    final commit = _json(
      await _send('POST', '/git/commits', {
        'message': message,
        'tree': tree['sha'],
        'parents': [parent.commit],
      }),
      'Commit',
    );
    final sha = commit['sha'] as String;
    final ref = await _send('PATCH', '/git/refs/heads/$branch', {'sha': sha, 'force': false});
    if (ref.statusCode == 422) return null;
    _json(ref, 'Push');
    return sha;
  }
}
