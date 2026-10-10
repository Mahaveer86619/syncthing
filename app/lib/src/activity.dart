import 'sync/engine.dart';

enum ActivityKind { synced, error, offline }

/// One line of the activity feed, stored as a JSON line in the app's private log file.
class Activity {
  Activity({
    required this.time,
    required this.kind,
    this.received = const [],
    this.sent = const [],
    this.removed = const [],
    this.conflicts = const [],
    this.message,
  });

  factory Activity.fromSummary(SyncSummary s) => Activity(
        time: DateTime.now(),
        kind: ActivityKind.synced,
        received: s.received.toList()..sort(),
        sent: s.sent.toList()..sort(),
        removed: ({...s.removedHere, ...s.removedThere}.toList())..sort(),
        conflicts: s.conflicts.toList()..sort(),
      );

  factory Activity.failure(Object error) => Activity(
        time: DateTime.now(),
        kind: error.toString().contains('SocketException') ? ActivityKind.offline : ActivityKind.error,
        message: error.toString(),
      );

  final DateTime time;
  final ActivityKind kind;
  final List<String> received, sent, removed, conflicts;
  final String? message;

  List<String> get allFiles => {...received, ...sent, ...removed}.toList()..sort();

  String get title {
    switch (kind) {
      case ActivityKind.offline:
        return 'Waiting for internet';
      case ActivityKind.error:
        return "Couldn't sync";
      case ActivityKind.synced:
        final files = allFiles;
        final noun = files.every((f) => f.endsWith('.md')) ? 'note' : 'file';
        return '${files.length} $noun${files.length == 1 ? '' : 's'} synced';
    }
  }

  String get subtitle {
    switch (kind) {
      case ActivityKind.offline:
        return "Will sync when you're back online";
      case ActivityKind.error:
        return _friendlyError(message ?? '');
      case ActivityKind.synced:
        return [
          if (sent.isNotEmpty) '${sent.length} sent',
          if (received.isNotEmpty) '${received.length} received',
          if (removed.isNotEmpty) '${removed.length} removed',
          if (conflicts.isNotEmpty)
            '${conflicts.length} edited on both sides (kept both)',
        ].join(' · ');
    }
  }

  static String _friendlyError(String m) {
    if (m.contains('401')) return 'GitHub token is wrong or expired. Update it in Settings';
    if (m.contains('not found')) return "Couldn't reach the notes repo. Check its name and token access";
    if (m.contains('Not an Obsidian vault')) return 'Pick your Obsidian vault folder in Settings';
    if (m.contains('Vault folder not found')) return 'Vault folder is missing. Pick it again in Settings';
    if (m.contains('empty')) return 'The notes repo is empty. Sync from the laptop first';
    return m.replaceFirst('Error: ', '');
  }

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'k': kind.name,
        if (received.isNotEmpty) 'in': received,
        if (sent.isNotEmpty) 'out': sent,
        if (removed.isNotEmpty) 'rm': removed,
        if (conflicts.isNotEmpty) 'cf': conflicts,
        if (message != null) 'msg': message,
      };

  factory Activity.fromJson(Map<String, dynamic> j) {
    List<String> list(String k) => (j[k] as List?)?.cast<String>() ?? const [];
    return Activity(
      time: DateTime.parse(j['t'] as String),
      kind: ActivityKind.values.byName(j['k'] as String),
      received: list('in'),
      sent: list('out'),
      removed: list('rm'),
      conflicts: list('cf'),
      message: j['msg'] as String?,
    );
  }
}
