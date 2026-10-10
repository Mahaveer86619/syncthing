import 'package:flutter/material.dart';

import '../config.dart';
import '../runner.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SyncConfig? _config;
  List<String> _log = [];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _reload();
    if (_config!.isComplete) await _sync();
  }

  Future<void> _reload() async {
    final config = await SyncConfig.load();
    final log = await readLog();
    if (!mounted) return;
    setState(() {
      _config = config;
      _log = log;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await runSync();
    _syncing = false;
    await _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final theme = Theme.of(context);
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(config.repo),
                      subtitle: Text(
                        '${config.vaultPath}\n'
                        '${config.intervalMinutes > 0 ? 'Background sync every ${config.intervalMinutes} min' : 'Background sync off'}',
                      ),
                      isThreeLine: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilledButton.icon(
                        onPressed: _syncing ? null : _sync,
                        icon: _syncing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text(_syncing ? 'Syncing…' : 'Sync now'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Expanded(
                      child: _log.isEmpty
                          ? const Center(child: Text('No syncs yet'))
                          : ListView.builder(
                              itemCount: _log.length,
                              itemBuilder: (_, i) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Text(_log[i], style: theme.textTheme.bodySmall),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}
