import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncConfig {
  SyncConfig({
    this.repo = '',
    this.branch = 'main',
    this.vaultPath = '',
    this.deviceName = 'phone',
    this.token = '',
    this.intervalMinutes = 15,
  });

  /// `owner/name`; a full GitHub URL is accepted and normalised.
  String repo;
  String branch;
  String vaultPath;
  String deviceName;
  String token;

  /// 0 disables background sync. Android will not run periodic work more often than every 15 min.
  int intervalMinutes;

  static const _secure = FlutterSecureStorage();

  bool get isComplete =>
      repo.split('/').length == 2 && branch.isNotEmpty && vaultPath.isNotEmpty && token.isNotEmpty;

  String get owner => repo.split('/').first;
  String get repoName => repo.split('/').last;

  static String normaliseRepo(String input) {
    var r = input.trim();
    r = r.replaceFirst(RegExp(r'^(https?://)?(www\.)?github\.com/'), '');
    r = r.replaceFirst(RegExp(r'^git@github\.com:'), '');
    r = r.replaceFirst(RegExp(r'\.git$'), '');
    return r.replaceAll(RegExp(r'/+$'), '');
  }

  /// Identifies the vault/remote pair so changing either starts from a clean sync state.
  String get stateKey => '$repo@$branch|$vaultPath';

  static Future<SyncConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return SyncConfig(
      repo: p.getString('repo') ?? '',
      branch: p.getString('branch') ?? 'main',
      vaultPath: p.getString('vaultPath') ?? '',
      deviceName: p.getString('deviceName') ?? 'phone',
      intervalMinutes: p.getInt('intervalMinutes') ?? 15,
      token: await _secure.read(key: 'token') ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('repo', normaliseRepo(repo));
    await p.setString('branch', branch.trim());
    await p.setString('vaultPath', vaultPath.trim());
    await p.setString('deviceName', deviceName.trim());
    await p.setInt('intervalMinutes', intervalMinutes);
    await _secure.write(key: 'token', value: token.trim());
  }
}
