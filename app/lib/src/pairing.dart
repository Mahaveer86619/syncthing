/// What the Windows app's pairing QR carries: `syncthing://pair?v=1&repo=..&branch=..&token=..`.
class Pairing {
  const Pairing(this.repo, this.branch, this.token);

  final String repo, branch, token;

  Uri toUri() => Uri(
        scheme: 'syncthing',
        host: 'pair',
        queryParameters: {'v': '1', 'repo': repo, 'branch': branch, 'token': token},
      );

  /// Null for null input (scan cancelled); throws for codes that are not ours.
  static Pairing? parse(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    final q = uri?.queryParameters ?? const {};
    if (uri == null || uri.scheme != 'syncthing' || uri.host != 'pair' ||
        (q['repo'] ?? '').split('/').length != 2 || (q['token'] ?? '').isEmpty) {
      throw const FormatException("That isn't a Syncthing pairing code");
    }
    return Pairing(q['repo']!, q['branch'] ?? 'main', q['token']!);
  }
}
