import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sync/plan.dart';

/// Settings shared with sync.ps1 through its config.json.
class LaptopConfig {
  LaptopConfig({
    this.repoPath = '',
    this.remoteUrl = '',
    this.branch = 'main',
    this.deviceName = 'laptop',
    this.debounceSeconds = 15,
    this.pollSeconds = 120,
  });

  factory LaptopConfig.fromJson(Map<String, dynamic> j) => LaptopConfig(
        // Older configs called the sync folder vaultPath.
        repoPath: j['repoPath'] as String? ?? j['vaultPath'] as String? ?? '',
        remoteUrl: j['remoteUrl'] as String? ?? '',
        branch: j['branch'] as String? ?? 'main',
        deviceName: j['deviceName'] as String? ?? 'laptop',
        debounceSeconds: (j['debounceSeconds'] as num?)?.toInt() ?? 15,
        pollSeconds: (j['pollSeconds'] as num?)?.toInt() ?? 120,
      );

  /// The git clone; the Obsidian vault is its obsidian-notes/ folder.
  String repoPath, remoteUrl, branch, deviceName;
  int debounceSeconds, pollSeconds;

  String get vaultDir => '$repoPath\\${notesPrefix.replaceAll('/', '')}';

  bool get isComplete => repoPath.isNotEmpty && remoteUrl.isNotEmpty && branch.isNotEmpty;

  /// `owner/repo` for display, whatever URL form was configured.
  String get repoLabel => remoteUrl
      .replaceFirst(RegExp(r'^.*github\.com[:/]'), '')
      .replaceFirst(RegExp(r'^.*:'), '')
      .replaceFirst(RegExp(r'\.git$'), '');

  Map<String, dynamic> toJson() => {
        'repoPath': repoPath,
        'remoteUrl': remoteUrl,
        'branch': branch,
        'deviceName': deviceName,
        'debounceSeconds': debounceSeconds,
        'pollSeconds': pollSeconds,
      };
}

class LaptopStatus {
  const LaptopStatus(this.state, this.message, this.time);

  /// `ok`, `offline` or `error`, as written by sync.ps1.
  final String state;
  final String message;
  final DateTime? time;
}

class Commit {
  const Commit(this.sha, this.author, this.time, this.subject, this.files);

  final String sha, author, subject;
  final DateTime time;
  final List<String> files;

  /// Commits made by either side start with `<device>: `.
  String get device => _legacy != null
      ? _legacy!.group(1)!
      : subject.contains(': ')
          ? subject.substring(0, subject.indexOf(': '))
          : author;
  String get summary => _legacy != null
      ? 'Synced'
      : subject.contains(': ')
          ? subject.substring(subject.indexOf(': ') + 2)
          : subject;

  /// Early commits were `sync: <device> <date> <time>`.
  RegExpMatch? get _legacy => RegExp(r'^sync: (\S+) \d{4}-').firstMatch(subject);
}

/// Drives the background sync (sync.ps1) that lives in %LOCALAPPDATA%\Syncthing.
/// The app is only a control panel: closing it leaves syncing running.
class LaptopSync {
  static final home = Directory('${Platform.environment['LOCALAPPDATA']}\\Syncthing');
  static const _scripts = ['sync.ps1', 'install-startup.ps1'];
  static const _window = MethodChannel('syncthing/window');
  static const _secure = FlutterSecureStorage();

  /// `syncthing-config/settings.json` inside the clone; it syncs like any other file.
  static Future<File> settingsFile() async {
    final c = await LaptopSync().readConfig();
    final root = c != null && c.repoPath.isNotEmpty ? c.repoPath : home.path;
    return File('$root\\${configPrefix.replaceAll('/', '')}\\settings.json');
  }

  /// Used only to build the phone pairing code; the laptop itself syncs with your git login.
  Future<String> phoneToken() async => await _secure.read(key: 'phoneToken') ?? '';

  Future<void> setPhoneToken(String token) => _secure.write(key: 'phoneToken', value: token.trim());

  /// Window, taskbar and shortcut icon for the shared `appIcon` setting (`mono` or anything else).
  Future<void> applyIcon(String mode) async {
    final name = mode == 'mono' ? 'mono' : 'default';
    final ico = _file('icon.ico');
    final data = await rootBundle.load('assets/icons/$name.ico');
    await ico.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await _window.invokeMethod('setIcon', ico.path);
    final links = [
      '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\Syncthing.lnk',
      '${Platform.environment['USERPROFILE']}\\Desktop\\Syncthing.lnk',
    ].where((l) => File(l).existsSync());
    if (links.isEmpty) return;
    final script = links
        .map((l) => "\$s = \$w.CreateShortcut('$l'); \$s.IconLocation = '${ico.path},0'; \$s.Save()")
        .join('; ');
    await Process.run('powershell.exe',
        ['-NoProfile', '-Command', "\$w = New-Object -ComObject WScript.Shell; $script"]);
  }

  /// Opens obsidian-notes as its own vault. `obsidian://open?path=` would pick any registered
  /// vault that merely contains the folder (e.g. the sync folder itself), so the vault is
  /// registered in Obsidian's list and opened by id. Returns a message when the user must act.
  Future<String?> openInObsidian(LaptopConfig c) async {
    final listFile = File('${Platform.environment['APPDATA']}\\obsidian\\obsidian.json');
    final list = await listFile.exists()
        ? jsonDecode(await listFile.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{};
    final vaults = (list['vaults'] as Map<String, dynamic>?) ?? {};
    String? id;
    vaults.forEach((key, v) {
      if ('${(v as Map)['path']}'.toLowerCase() == c.vaultDir.toLowerCase()) id = key;
    });
    if (id == null) {
      final running = await Process.run('tasklist', ['/FI', 'IMAGENAME eq Obsidian.exe', '/NH']);
      // Obsidian rewrites its vault list on exit, so it can only be edited while closed.
      if ('${running.stdout}'.contains('Obsidian.exe')) {
        return 'In Obsidian choose Open another vault → Open folder as vault → ${c.vaultDir}, '
            'or close Obsidian and click again';
      }
      final rnd = Random.secure();
      id = List.generate(8, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      vaults[id!] = {'path': c.vaultDir, 'ts': DateTime.now().millisecondsSinceEpoch};
      list['vaults'] = vaults;
      await listFile.parent.create(recursive: true);
      await listFile.writeAsString(jsonEncode(list));
    }
    await Process.run('cmd', ['/c', 'start', '', 'obsidian://open?vault=$id']);
    return null;
  }

  File _file(String name) => File('${home.path}\\$name');
  File get _startupLink => File('${Platform.environment['APPDATA']}\\Microsoft\\Windows\\'
      'Start Menu\\Programs\\Startup\\syncthing-vault-sync.lnk');

  /// Copies the bundled scripts out, restarting the background sync if they changed.
  Future<void> installScripts() async {
    await home.create(recursive: true);
    var changed = false;
    for (final name in _scripts) {
      final bundled = await rootBundle.loadString('assets/sync/$name');
      final f = _file(name);
      if (!await f.exists() || await f.readAsString() != bundled) {
        await f.writeAsString(bundled);
        changed = true;
      }
    }
    if (changed && await isRunning()) await restart();
  }

  Future<LaptopConfig?> readConfig() async {
    final f = _file('config.json');
    if (!await f.exists()) return null;
    return LaptopConfig.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  Future<void> writeConfig(LaptopConfig c) =>
      _file('config.json').writeAsString(const JsonEncoder.withIndent('  ').convert(c.toJson()));

  Future<bool> isRunning() async {
    final pidFile = _file('logs\\daemon.pid');
    if (!await pidFile.exists()) return false;
    final pid = (await pidFile.readAsString()).trim();
    final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
    return (r.stdout as String).toLowerCase().contains('powershell.exe');
  }

  Future<bool> startsAtLogin() => _startupLink.exists();

  Future<ProcessResult> _powershell(List<String> args) => Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ...args],
        workingDirectory: home.path,
      );

  /// Starts the background sync now and at every login.
  Future<void> enable() async => _powershell([_file('install-startup.ps1').path]);

  Future<void> disable() async => _powershell([_file('install-startup.ps1').path, '-Uninstall']);

  Future<void> restart() async {
    await disable();
    await enable();
  }

  /// One-time: turns the vault into a clone of the notes repo. Returns an error message on failure.
  Future<String?> connectVault() async {
    final r = await _powershell([_file('sync.ps1').path, '-Init']);
    if (r.exitCode == 0) return null;
    final err = '${r.stderr}'.trim();
    return err.isEmpty ? '${r.stdout}'.trim() : err.split('\n').first;
  }

  /// Asks the running background sync for an immediate full sync, or runs one directly.
  Future<void> syncNow() async {
    if (await isRunning()) {
      final trigger = _file('sync-now');
      await trigger.writeAsString('');
      // The background loop wakes every 5 s; wait for it to pick the request up and finish.
      final before = (await status())?.time;
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final now = (await status())?.time;
        if (!await trigger.exists() && now != null && now != before) return;
      }
      return;
    }
    await _powershell([_file('sync.ps1').path, '-Once']);
  }

  Future<LaptopStatus?> status() async {
    final f = _file('logs\\status.json');
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return LaptopStatus(
        j['state'] as String? ?? 'ok',
        j['message'] as String? ?? '',
        DateTime.tryParse(j['time'] as String? ?? ''),
      );
    } on FormatException {
      return null;
    }
  }

  Future<DateTime?> nextPoll(LaptopConfig c) async {
    final f = _file('logs\\last_poll');
    if (!await f.exists()) return null;
    final last = DateTime.tryParse((await f.readAsString()).trim());
    return last?.add(Duration(seconds: c.pollSeconds));
  }

  Future<int> noteCount(LaptopConfig c) async {
    final r = await Process.run('git', ['-C', c.repoPath, 'ls-files', '--', '$notesPrefix*.md']);
    if (r.exitCode != 0) return 0;
    return const LineSplitter().convert('${r.stdout}').where((l) => l.isNotEmpty).length;
  }

  /// The diff one commit made to one file (vault-relative path), from local history.
  Future<String> patch(LaptopConfig c, String sha, String path) async {
    // Commits from before the repo layout stored notes at the root.
    for (final p in ['$notesPrefix$path', path]) {
      final r = await Process.run(
        'git',
        ['-C', c.repoPath, '-c', 'core.quotepath=false', 'show', '--format=', '--unified=2', sha, '--', p],
        stdoutEncoding: utf8,
      );
      final out = '${r.stdout}';
      if (out.trim().isNotEmpty) {
        // Drop the diff/index/---/+++ preamble; keep hunks.
        final at = out.indexOf('\n@@');
        return at < 0 ? '' : out.substring(at + 1);
      }
    }
    return '';
  }

  /// Recent commits from every device, newest first.
  Future<List<Commit>> history(LaptopConfig c, {int count = 40}) async {
    final r = await Process.run(
      'git',
      [
        '-C', c.repoPath, '-c', 'core.quotepath=false', 'log', '-n', '$count', '--name-only',
        '--format=%x1e%H%x1f%an%x1f%aI%x1f%s',
      ],
      stdoutEncoding: utf8,
    );
    if (r.exitCode != 0) return [];
    final out = <Commit>[];
    for (final chunk in '${r.stdout}'.split('\x1e')) {
      final lines = const LineSplitter().convert(chunk.trim());
      if (lines.isEmpty) continue;
      final f = lines.first.split('\x1f');
      if (f.length < 4) continue;
      out.add(Commit(
        f[0],
        f[1],
        DateTime.parse(f[2]).toLocal(),
        f[3],
        lines.skip(1).where((l) => l.trim().isNotEmpty).map(displayPath).toList(),
      ));
    }
    return out;
  }
}
