import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncthing/src/sync/github.dart';

void main() {
  test('tree request sends recursive as a query parameter, not in the path', () async {
    late Uri seen;
    final repo = GitHubRepo(
      owner: 'me',
      repo: 'notes',
      branch: 'main',
      token: 't',
      client: MockClient((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode({
            'truncated': false,
            'tree': [
              {'path': 'a.md', 'type': 'blob', 'mode': '100644', 'sha': '1'},
              {'path': 'dir', 'type': 'tree', 'mode': '040000', 'sha': '2'},
            ],
          }),
          200,
        );
      }),
    );
    expect(await repo.tree('abc'), {'a.md': '1'});
    expect(seen.path, '/repos/me/notes/git/trees/abc');
    expect(seen.queryParameters, {'recursive': '1'});
  });
}
