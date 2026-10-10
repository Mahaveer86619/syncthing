enum ActionKind { download, upload, deleteLocal, deleteRemote, conflict }

class SyncAction {
  const SyncAction(this.kind, this.path);

  final ActionKind kind;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is SyncAction && other.kind == kind && other.path == path;

  @override
  int get hashCode => Object.hash(kind, path);

  @override
  String toString() => '${kind.name}:$path';
}

/// Three-way comparison of path -> blob sha maps against the state at the last sync.
List<SyncAction> planSync({
  required Map<String, String> base,
  required Map<String, String> local,
  required Map<String, String> remote,
}) {
  final paths = {...base.keys, ...local.keys, ...remote.keys}.toList()..sort();
  final actions = <SyncAction>[];
  for (final p in paths) {
    final b = base[p], l = local[p], r = remote[p];
    if (l == r) continue;
    if (r == b) {
      actions.add(SyncAction(l == null ? ActionKind.deleteRemote : ActionKind.upload, p));
    } else if (l == b) {
      actions.add(SyncAction(r == null ? ActionKind.deleteLocal : ActionKind.download, p));
    } else if (l == null) {
      // Deleted here, edited there: the edit wins.
      actions.add(SyncAction(ActionKind.download, p));
    } else if (r == null) {
      actions.add(SyncAction(ActionKind.upload, p));
    } else {
      actions.add(SyncAction(ActionKind.conflict, p));
    }
  }
  return actions;
}

String conflictPath(String path, DateTime now) {
  final slash = path.lastIndexOf('/');
  final dir = slash >= 0 ? path.substring(0, slash + 1) : '';
  final file = path.substring(slash + 1);
  final dot = file.lastIndexOf('.');
  final name = dot > 0 ? file.substring(0, dot) : file;
  final ext = dot > 0 ? file.substring(dot) : '';
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return '$dir$name (conflict $stamp)$ext';
}
