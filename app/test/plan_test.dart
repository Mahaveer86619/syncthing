import 'package:flutter_test/flutter_test.dart';
import 'package:syncthing/src/sync/ignore.dart';
import 'package:syncthing/src/sync/plan.dart';

void main() {
  group('planSync', () {
    List<String> plan(Map<String, String> b, Map<String, String> l, Map<String, String> r) =>
        planSync(base: b, local: l, remote: r).map((a) => a.toString()).toList();

    test('unchanged and identical files need nothing', () {
      expect(plan({'a': '1'}, {'a': '1'}, {'a': '1'}), isEmpty);
      expect(plan({}, {'a': '2'}, {'a': '2'}), isEmpty);
    });

    test('one-sided edits flow to the other side', () {
      expect(plan({'a': '1'}, {'a': '2'}, {'a': '1'}), ['upload:a']);
      expect(plan({'a': '1'}, {'a': '1'}, {'a': '2'}), ['download:a']);
      expect(plan({}, {'n': '1'}, {}), ['upload:n']);
      expect(plan({}, {}, {'n': '1'}), ['download:n']);
    });

    test('one-sided deletes propagate', () {
      expect(plan({'a': '1'}, {}, {'a': '1'}), ['deleteRemote:a']);
      expect(plan({'a': '1'}, {'a': '1'}, {}), ['deleteLocal:a']);
      expect(plan({'a': '1'}, {}, {}), isEmpty);
    });

    test('edit beats delete', () {
      expect(plan({'a': '1'}, {}, {'a': '2'}), ['download:a']);
      expect(plan({'a': '1'}, {'a': '2'}, {}), ['upload:a']);
    });

    test('both edited is a conflict, including first sync with differing files', () {
      expect(plan({'a': '1'}, {'a': '2'}, {'a': '3'}), ['conflict:a']);
      expect(plan({}, {'a': '2'}, {'a': '3'}), ['conflict:a']);
    });
  });

  test('conflictPath keeps folder and extension', () {
    final t = DateTime(2026, 10, 10, 9, 5, 7);
    expect(conflictPath('dir/note.md', t), 'dir/note (conflict 2026-10-10 090507).md');
    expect(conflictPath('README', t), 'README (conflict 2026-10-10 090507)');
  });

  test('IgnoreRules follows common .gitignore patterns', () {
    final r = IgnoreRules.fromGitignore('*.tmp\n/build/\n.obsidian/cache\n# comment\n');
    expect(r.ignores('.git/config'), isTrue);
    expect(r.ignores('.obsidian/workspace.json'), isTrue);
    expect(r.ignores('.obsidian/app.json'), isFalse);
    expect(r.ignores('.obsidian/cache'), isTrue);
    expect(r.ignores('notes/x.tmp'), isTrue);
    expect(r.ignores('build/out.md'), isTrue);
    expect(r.ignores('notes/build/out.md'), isFalse);
    expect(r.ignores('.trash/old.md'), isTrue);
    expect(r.ignores('notes/today.md'), isFalse);
  });
}
