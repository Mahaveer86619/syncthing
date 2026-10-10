import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../shared_settings.dart';
import '../ui/theme_choice.dart';
import '../ui/widgets.dart';
import 'desktop_settings.dart';
import 'laptop_sync.dart';

class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    // On Windows the dynamic seed is the system accent colour.
    return DynamicColorBuilder(
      builder: (light, dark) => ValueListenableBuilder<Color?>(
        valueListenable: ThemeChoice.seed,
        builder: (context, chosen, _) => MaterialApp(
          title: 'Syncthing',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(chosen ?? light?.primary ?? seedColor, Brightness.light),
          darkTheme: buildTheme(chosen ?? dark?.primary ?? seedColor, Brightness.dark),
          home: const DesktopHome(),
        ),
      ),
    );
  }
}

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  final _sync = LaptopSync();
  LaptopConfig? _config;
  bool _loaded = false;
  bool _running = false;
  bool _atLogin = false;
  bool _busy = false;
  LaptopStatus? _status;
  DateTime? _nextPoll;
  List<Commit> _history = [];
  int _notes = 0;
  Timer? _refresh;
  String? _appliedIcon;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _sync.installScripts();
    await _reload();
    // Cheap file reads plus one tasklist call; keeps the window honest while it is open.
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _reload());
  }

  Future<void> _reload() async {
    // Picks up theme and icon changes made on the phone once they have synced down.
    await ThemeChoice.load();
    final icon = (await SharedSettings.read())['appIcon'] as String? ?? 'auto';
    if (icon != _appliedIcon) {
      _appliedIcon = icon;
      await _sync.applyIcon(icon);
    }
    final config = await _sync.readConfig();
    final running = await _sync.isRunning();
    final atLogin = await _sync.startsAtLogin();
    final status = await _sync.status();
    final ready = config != null && config.isComplete;
    final next = ready ? await _sync.nextPoll(config) : null;
    final historyChanged = status?.time != _status?.time || _history.isEmpty;
    final history = ready && historyChanged ? await _sync.history(config) : _history;
    final notes = ready && historyChanged ? await _sync.noteCount(config) : _notes;
    if (!mounted) return;
    setState(() {
      _config = config;
      _running = running;
      _atLogin = atLogin;
      _status = status;
      _nextPoll = next;
      _history = history;
      _notes = notes;
      _loaded = true;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    await _sync.syncNow();
    _history = [];
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setAutoSync(bool on) async {
    setState(() => _busy = true);
    on ? await _sync.enable() : await _sync.disable();
    await Future<void>.delayed(const Duration(seconds: 2));
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DesktopSettings(sync: _sync, running: _running)),
    );
    if (saved == true) _history = [];
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (config == null || !config.isComplete) {
      return Scaffold(body: _Welcome(onStart: _openSettings));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncthing'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 880;
          final left = [_statusCard(config), _autoSyncCard()];
          final activity = _activity();
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [...left, ...activity],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 440,
                child: ListView(padding: const EdgeInsets.only(bottom: 32), children: left),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.only(bottom: 32), children: activity),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(LaptopConfig config) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _status;
    final (IconData icon, Color bg, Color fg, String headline, String detail) = _busy
        ? (Icons.sync_rounded, scheme.primary, scheme.onPrimary, 'Syncing…', 'Talking to GitHub')
        : !_running && !_atLogin
            ? (Icons.pause_rounded, scheme.surfaceContainerHighest, scheme.onSurfaceVariant,
                'Paused', 'Auto sync is off')
            : s?.state == 'offline'
                ? (Icons.cloud_off_rounded, scheme.tertiaryContainer, scheme.onTertiaryContainer,
                    'Offline', "Will sync when you're back online")
                : s?.state == 'error'
                    ? (Icons.priority_high_rounded, scheme.errorContainer,
                        scheme.onErrorContainer, 'Needs attention', s!.message)
                    : (Icons.done_all_rounded, scheme.primaryContainer,
                        scheme.onPrimaryContainer, 'All synced',
                        s?.time == null ? 'Waiting for the first check' : 'Checked ${ago(s!.time!)}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Card(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShapeBadge(icon: icon, color: bg, onColor: fg, busy: _busy, size: 88),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headline, style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text(detail,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text('$_notes notes'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open in Obsidian'),
                    tooltip: config.vaultDir,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final note = await _sync.openInObsidian(config);
                      if (note != null) messenger.showSnackBar(SnackBar(content: Text(note)));
                    },
                  ),
                  Chip(
                    avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text(config.repoLabel),
                  ),
                ],
              ),
              if (_running && _nextPoll != null) ...[
                const SizedBox(height: 16),
                NextCheck(
                  _nextPoll!,
                  interval: Duration(seconds: config.pollSeconds),
                  label: 'Next check for phone changes',
                  onOverdue: _reload,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _syncNow,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(_busy ? 'Syncing…' : 'Sync now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _autoSyncCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = _running || _atLogin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: on ? scheme.secondaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(on ? 28 : 40),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: _busy ? null : () => _setAutoSync(!on),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                TonalIcon(
                  on ? Icons.bolt_rounded : Icons.pause_rounded,
                  color: on ? scheme.secondary : scheme.surfaceContainerHighest,
                  onColor: on ? scheme.onSecondary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto sync', style: theme.textTheme.titleLarge),
                      Text(
                        on
                            ? 'Runs in the background and at every login, even with this window closed'
                            : 'Paused. Only syncs when you tap Sync now',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(value: on, onChanged: _busy ? null : _setAutoSync),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _activity() {
    final theme = Theme.of(context);
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
        child: Text('Activity', style: theme.textTheme.headlineSmall),
      ),
    ];
    if (_history.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Changes from this laptop and your phone will be listed here.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ));
      return rows;
    }
    final days = <String, List<Commit>>{};
    for (final c in _history) {
      days.putIfAbsent(dayLabel(c.time), () => []).add(c);
    }
    for (final day in days.entries) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 24, 8),
        child: Text(day.key,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
      ));
      for (var i = 0; i < day.value.length; i++) {
        rows.add(_CommitTile(day.value[i],
            sync: _sync, config: _config!, first: i == 0, last: i == day.value.length - 1));
      }
    }
    return rows;
  }
}

class _CommitTile extends StatelessWidget {
  const _CommitTile(this.commit,
      {required this.sync, required this.config, required this.first, required this.last});

  final Commit commit;
  final LaptopSync sync;
  final LaptopConfig config;
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = commit;
    final fromPhone = RegExp('phone|mobile|android', caseSensitive: false).hasMatch(c.device);
    final merge = c.summary.startsWith('merge');
    final (IconData icon, Color bg, Color fg) = merge
        ? (Icons.merge_rounded, scheme.tertiaryContainer, scheme.onTertiaryContainer)
        : fromPhone
            ? (Icons.smartphone_rounded, scheme.secondaryContainer, scheme.onSecondaryContainer)
            : (Icons.laptop_rounded, scheme.primaryContainer, scheme.onPrimaryContainer);
    const outer = Radius.circular(24), inner = Radius.circular(6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Material(
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: first ? outer : inner,
            bottom: last ? outer : inner,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          leading: TonalIcon(icon, color: bg, onColor: fg),
          title: Text(c.summary, style: theme.textTheme.titleMedium),
          subtitle: Text('${c.device} · ${c.author}'),
          trailing: Text(clockTime(c.time), style: theme.textTheme.labelMedium),
          onTap: c.files.isEmpty ? null : () => _showFiles(context),
        ),
      ),
    );
  }

  void _showFiles(BuildContext context) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(commit.summary),
        content: SizedBox(
          width: 640,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('${commit.device} · ${commit.author} · ${dayLabel(commit.time)} '
                  '${clockTime(commit.time)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final path in commit.files)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  shape: const Border(),
                  leading: Icon(path.endsWith('.md')
                      ? Icons.description_outlined
                      : Icons.insert_drive_file_outlined),
                  title: Text(path.split('/').last.replaceFirst(RegExp(r'\.md$'), '')),
                  subtitle: path.contains('/')
                      ? Text(path.substring(0, path.lastIndexOf('/')))
                      : null,
                  children: [
                    FutureBuilder<String>(
                      future: sync.patch(config, commit.sha, path),
                      builder: (context, snap) => snap.connectionState != ConnectionState.done
                          ? const LinearProgressIndicator()
                          : (snap.data ?? '').isEmpty
                              ? const Text('No text changes to show')
                              : DiffView(snap.data!),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShapeBadge(
                icon: Icons.sync_rounded,
                color: scheme.primaryContainer,
                onColor: scheme.onPrimaryContainer,
                size: 120,
              ),
              const SizedBox(height: 32),
              Text('Your notes,\neverywhere.', style: theme.textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                'Keep your Obsidian vault on this PC in sync with your phone through a '
                'private GitHub repo. Syncing keeps running in the background after you '
                'close this window.',
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
