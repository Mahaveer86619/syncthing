import 'package:flutter/material.dart';

import '../config.dart';
import '../runner.dart';
import '../schedule.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SyncConfig? _config;
  List<String> _log = [];
  DateTime? _lastCheck;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _init() async {
    await _reload();
    final config = _config!;
    if (!config.isComplete) return;
    // Re-registering is idempotent and heals schedules lost to app updates or "force stop".
    await applySchedule(config.autoSync);
    await _sync();
  }

  Future<void> _reload() async {
    final config = await SyncConfig.load();
    final log = await readLog();
    final last = await lastCheck();
    if (!mounted) return;
    setState(() {
      _config = config;
      _log = log;
      _lastCheck = last;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await runSync();
    _syncing = false;
    await _reload();
  }

  Future<void> _setAutoSync(bool on) async {
    final config = _config!..autoSync = on;
    setState(() {});
    await config.save();
    await applySchedule(on);
    if (on) await _sync();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    await _reload();
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncthing'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings)],
      ),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : !config.isComplete
              ? Center(
                  child: FilledButton(
                    onPressed: _openSettings,
                    child: const Text('Set up notes repo'),
                  ),
                )
              : _buildStatus(config),
    );
  }

  Widget _buildStatus(SyncConfig config) {
    final theme = Theme.of(context);
    final status = _syncing
        ? 'Syncing…'
        : _lastCheck == null
            ? 'Not synced yet'
            : 'Last checked ${_ago(_lastCheck!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              SwitchListTile(
                value: config.autoSync,
                onChanged: _setAutoSync,
                title: Text('Auto sync', style: theme.textTheme.titleMedium),
                subtitle: Text(config.autoSync
                    ? 'On: syncs after you edit notes, and checks the laptop\'s changes every 15 min'
                    : 'Off: only syncs when you tap Sync now'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: _syncing
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_done_outlined),
                title: Text(status),
                subtitle: Text('${config.repo} · ${config.vaultPath}'),
                trailing: OutlinedButton(
                  onPressed: _syncing ? null : _sync,
                  child: const Text('Sync now'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Activity', style: theme.textTheme.titleSmall),
        ),
        Expanded(
          child: _log.isEmpty
              ? const Center(child: Text('No changes synced yet'))
              : ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(_log[i], style: theme.textTheme.bodySmall),
                  ),
                ),
        ),
      ],
    );
  }
}
