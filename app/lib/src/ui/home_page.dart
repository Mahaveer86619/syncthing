import 'package:flutter/material.dart';

import '../activity.dart';
import '../config.dart';
import '../festival.dart';
import '../runner.dart';
import '../schedule.dart';
import 'theme_choice.dart';
import 'settings_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SyncConfig? _config;
  List<Activity> _activity = [];
  DateTime? _lastCheck;
  int _notes = 0;
  DateTime? _nextPoll;
  Festival? _festival;
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
    if (state != AppLifecycleState.resumed) return;
    // Resuming a frozen process skips initState, so the schedule is checked here too.
    _healSchedule();
    _reload();
  }

  Future<void> _healSchedule() async {
    final config = _config ?? await SyncConfig.load();
    if (!config.isComplete || !config.autoSync) return;
    if (await ensureSchedule()) {
      await recordRestart();
      await _reload();
    }
  }

  Future<void> _init() async {
    await _reload();
    Festival.today().then((f) => mounted ? setState(() => _festival = f) : null);
    final config = _config!;
    if (!config.isComplete) return;
    config.autoSync ? await _healSchedule() : await applySchedule(false);
    await _sync();
  }

  Future<void> _reload() async {
    await ThemeChoice.load();
    final config = await SyncConfig.load();
    final activity = await readActivity();
    final last = await lastCheck();
    final notes = await syncedNoteCount();
    final next = await nextPoll();
    if (!mounted) return;
    setState(() {
      _config = config;
      _activity = activity;
      _lastCheck = last;
      _notes = notes;
      _nextPoll = next;
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
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const SettingsPage()));
    await _reload();
    if (saved == true && _config!.isComplete) await _sync();
  }

  /// The newest feed entry is a failure that no successful check has superseded yet.
  bool get _failing {
    final latest = _activity.isEmpty ? null : _activity.first;
    return latest != null &&
        (latest.kind == ActivityKind.error || latest.kind == ActivityKind.offline) &&
        (_lastCheck == null || latest.time.isAfter(_lastCheck!));
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) return const Scaffold();
    if (!config.isComplete) return Scaffold(body: _Welcome(onStart: _openSettings));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncthing'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: CustomScrollView(
          slivers: [
            if (_festival != null) SliverToBoxAdapter(child: _FestivalBanner(_festival!)),
            SliverToBoxAdapter(child: _statusCard(config)),
            SliverToBoxAdapter(child: _autoSyncCard(config)),
            ..._activitySlivers(),
            SliverToBoxAdapter(
              child: SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(SyncConfig config) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failing = _failing;
    final latest = failing ? _activity.first : null;

    final (IconData icon, Color bg, Color fg, String headline, String detail) = _syncing
        ? (Icons.sync_rounded, scheme.primary, scheme.onPrimary, 'Syncing…', 'Talking to GitHub')
        : failing && latest!.kind == ActivityKind.offline
            ? (Icons.cloud_off_rounded, scheme.tertiaryContainer, scheme.onTertiaryContainer,
                'Offline', latest.subtitle)
            : failing
                ? (Icons.priority_high_rounded, scheme.errorContainer, scheme.onErrorContainer,
                    'Needs attention', latest!.subtitle)
                : _lastCheck == null
                    ? (Icons.cloud_upload_rounded, scheme.secondaryContainer,
                        scheme.onSecondaryContainer, 'Ready', 'Pull down or tap Sync now')
                    : (Icons.done_all_rounded, scheme.primaryContainer, scheme.onPrimaryContainer,
                        'All synced', 'Checked ${ago(_lastCheck!)}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Card(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShapeBadge(icon: icon, color: bg, onColor: fg, busy: _syncing, size: 88),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(headline,
                              key: ValueKey(headline), style: theme.textTheme.displaySmall),
                        ),
                        const SizedBox(height: 4),
                        Text(detail,
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
                  Chip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(config.vaultPath.split('/').last),
                  ),
                ],
              ),
              if (config.autoSync && _nextPoll != null) ...[
                const SizedBox(height: 16),
                NextCheck(_nextPoll!, interval: pollInterval, onOverdue: _reload),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _syncing ? null : _sync,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(_syncing ? 'Syncing…' : 'Sync now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _autoSyncCard(SyncConfig config) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = config.autoSync;
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
          onTap: () => _setAutoSync(!on),
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
                            ? 'Right after you edit, plus a check every 15 min'
                            : 'Paused. Only syncs when you tap Sync now',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(value: on, onChanged: _setAutoSync),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _activitySlivers() {
    final theme = Theme.of(context);
    final header = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
        child: Text('Activity', style: theme.textTheme.headlineSmall),
      ),
    );
    if (_activity.isEmpty) {
      return [
        header,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Column(
                  children: [
                    ShapeBadge(
                      icon: Icons.history_rounded,
                      color: theme.colorScheme.secondaryContainer,
                      onColor: theme.colorScheme.onSecondaryContainer,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text('Nothing new to show', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      _lastCheck == null
                          ? 'Edits from this phone and your laptop will be listed here.'
                          : 'Everything matched at the last check. Edits from this phone '
                              'and your laptop will be listed here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    final days = <String, List<Activity>>{};
    for (final a in _activity) {
      days.putIfAbsent(dayLabel(a.time), () => []).add(a);
    }
    final rows = <Widget>[];
    for (final day in days.entries) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 24, 8),
        child: Text(day.key,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
      ));
      for (var i = 0; i < day.value.length; i++) {
        rows.add(_ActivityTile(day.value[i], first: i == 0, last: i == day.value.length - 1));
      }
    }
    return [header, SliverList.list(children: rows)];
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile(this.activity, {required this.first, required this.last});

  final Activity activity;

  /// Position inside its day group: M3 Expressive segmented lists round only the outer corners.
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = activity;
    final (IconData icon, Color bg, Color fg) = switch (a.kind) {
      ActivityKind.synced when a.conflicts.isNotEmpty =>
        (Icons.call_split_rounded, scheme.tertiaryContainer, scheme.onTertiaryContainer),
      ActivityKind.synced when a.sent.isNotEmpty && a.received.isEmpty =>
        (Icons.north_rounded, scheme.primaryContainer, scheme.onPrimaryContainer),
      ActivityKind.synced when a.received.isNotEmpty && a.sent.isEmpty =>
        (Icons.south_rounded, scheme.secondaryContainer, scheme.onSecondaryContainer),
      ActivityKind.synced => (Icons.sync_alt_rounded, scheme.primaryContainer, scheme.onPrimaryContainer),
      ActivityKind.offline => (Icons.cloud_off_rounded, scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      ActivityKind.restarted => (Icons.restart_alt_rounded, scheme.tertiaryContainer, scheme.onTertiaryContainer),
      ActivityKind.error => (Icons.priority_high_rounded, scheme.errorContainer, scheme.onErrorContainer),
    };
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
          title: Text(a.title, style: theme.textTheme.titleMedium),
          subtitle: Text(a.subtitle),
          trailing: Text(clockTime(a.time), style: theme.textTheme.labelMedium),
          onTap: a.kind == ActivityKind.synced ? () => _showDetails(context) : null,
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final theme = Theme.of(context);
    final a = activity;
    final groups = {
      'Sent to GitHub': a.sent,
      'Received': a.received,
      'Removed': a.removed,
      'Edited on both sides, both versions kept': a.conflicts,
    }..removeWhere((_, v) => v.isEmpty);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text(a.title, style: theme.textTheme.headlineSmall),
            Text('${dayLabel(a.time)} at ${clockTime(a.time)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Text('${g.key} · ${g.value.length}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
              for (final path in g.value)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(path.endsWith('.md')
                      ? Icons.description_outlined
                      : Icons.insert_drive_file_outlined),
                  title: Text(path.split('/').last.replaceFirst(RegExp(r'\.md$'), '')),
                  subtitle: path.contains('/')
                      ? Text(path.substring(0, path.lastIndexOf('/')))
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FestivalBanner extends StatelessWidget {
  const _FestivalBanner(this.festival);

  final Festival festival;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            theme.colorScheme.tertiaryContainer,
            theme.colorScheme.primaryContainer,
          ]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(festival.icon, size: 30, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Text(festival.greeting,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
            ),
          ],
        ),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
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
              'Keep your Obsidian vault in sync between this phone and your laptop '
              'through a private GitHub repo. No server, no subscription.',
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(flex: 2),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Get started'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
