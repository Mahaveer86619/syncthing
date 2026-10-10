/// The subset of .gitignore syntax a vault realistically uses: `*`, `**`, `?`,
/// trailing `/` for directories and leading `/` for anchoring. Negation is not supported.
class IgnoreRules {
  IgnoreRules(Iterable<String> patterns)
      : _rules = patterns.map(_toRegExp).whereType<RegExp>().toList();

  factory IgnoreRules.fromGitignore(String? content) =>
      IgnoreRules([...defaults, ...?content?.split('\n')]);

  static const defaults = [
    '.git/',
    '.obsidian/workspace.json',
    '.obsidian/workspace-mobile.json',
    '.trash/',
  ];

  final List<RegExp> _rules;

  bool ignores(String path) => _rules.any((r) => r.hasMatch(path));

  static RegExp? _toRegExp(String line) {
    var p = line.trim();
    if (p.isEmpty || p.startsWith('#') || p.startsWith('!')) return null;
    final dirOnly = p.endsWith('/');
    if (dirOnly) p = p.substring(0, p.length - 1);
    final anchored = p.contains('/');
    if (p.startsWith('/')) p = p.substring(1);

    final body = StringBuffer();
    for (var i = 0; i < p.length; i++) {
      final c = p[i];
      if (c == '*' && i + 1 < p.length && p[i + 1] == '*') {
        body.write('.*');
        i++;
      } else if (c == '*') {
        body.write('[^/]*');
      } else if (c == '?') {
        body.write('[^/]');
      } else {
        body.write(RegExp.escape(c));
      }
    }
    final prefix = anchored ? '^' : '(^|/)';
    final suffix = dirOnly ? '/.*' : '(/.*)?';
    return RegExp('$prefix$body$suffix\$');
  }
}
