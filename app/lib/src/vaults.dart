import 'dart:io';

const sharedStorage = '/storage/emulated/0';

bool isVault(String path) => Directory('$path/.obsidian').existsSync();

// Media and app-data folders are large and never hold vaults; walking them made Settings slow.
const _skip = {
  'Android', 'DCIM', 'Pictures', 'Movies', 'Music', 'Ringtones', 'Alarms', 'Notifications',
  'Podcasts', 'Audiobooks', 'Recordings', 'WhatsApp', 'Telegram', 'MIUI', 'Snapchat',
};

/// Obsidian vaults in shared storage (folders holding a `.obsidian` directory), shallowest first.
Future<List<String>> findVaults({String root = sharedStorage, int maxDepth = 3}) async {
  final found = <String>[];
  Future<void> walk(Directory dir, int depth) async {
    if (isVault(dir.path)) {
      found.add(dir.path);
      return;
    }
    if (depth == maxDepth) return;
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = e.path.split('/').last;
        if (e is Directory && !name.startsWith('.') && !_skip.contains(name)) {
          await walk(e, depth + 1);
        }
      }
    } on FileSystemException {
      // Unreadable folder; skip it.
    }
  }

  await walk(Directory(root), 0);
  return found;
}

/// Picking the folder that contains a single vault (e.g. `Obsidian/`) means that vault.
Future<String> resolveVault(String path) async {
  if (isVault(path)) return path;
  final inside = await findVaults(root: path, maxDepth: 1);
  return inside.length == 1 ? inside.first : path;
}
