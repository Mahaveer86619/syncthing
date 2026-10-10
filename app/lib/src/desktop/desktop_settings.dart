import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../festival.dart';
import '../pairing.dart';
import '../shared_settings.dart';
import '../ui/theme_choice.dart';
import '../ui/widgets.dart';
import 'laptop_sync.dart';

class DesktopSettings extends StatefulWidget {
  const DesktopSettings({super.key, required this.sync, required this.running});

  final LaptopSync sync;
  final bool running;

  @override
  State<DesktopSettings> createState() => _DesktopSettingsState();
}

class _DesktopSettingsState extends State<DesktopSettings> {
  final _form = GlobalKey<FormState>();
  final _vault = TextEditingController();
  final _remote = TextEditingController();
  final _branch = TextEditingController();
  final _device = TextEditingController();
  final _token = TextEditingController();
  bool _showToken = false;
  String _iconMode = 'auto';
  int _debounce = 15;
  int _poll = 120;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await widget.sync.readConfig() ??
        LaptopConfig(
          repoPath: '${Platform.environment['USERPROFILE']}\\Syncthing',
          deviceName: Platform.localHostname.toLowerCase(),
        );
    final token = await widget.sync.phoneToken();
    final icon = (await SharedSettings.read())['appIcon'] as String? ?? 'auto';
    setState(() {
      _token.text = token;
      _iconMode = icon;
      _vault.text = c.repoPath;
      _remote.text = c.remoteUrl;
      _branch.text = c.branch;
      _device.text = c.deviceName;
      _debounce = c.debounceSeconds;
      _poll = c.pollSeconds;
    });
  }

  Future<void> _pickVault() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Sync folder');
    if (path != null) setState(() => _vault.text = path);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.sync.setPhoneToken(_token.text);
    await widget.sync.writeConfig(LaptopConfig(
      repoPath: _vault.text.trim(),
      remoteUrl: _remote.text.trim(),
      branch: _branch.text.trim(),
      deviceName: _device.text.trim(),
      debounceSeconds: _debounce,
      pollSeconds: _poll,
    ));
    // A folder that is not a clone yet gets attached to the repo (and organised) first.
    if (!await Directory('${_vault.text.trim()}\\.git').exists()) {
      final err = await widget.sync.connectVault();
      if (err != null) {
        setState(() {
          _saving = false;
          _error = err;
        });
        return;
      }
      await widget.sync.enable();
    } else if (widget.running) {
      await widget.sync.restart();
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _setIconMode(String mode) async {
    setState(() => _iconMode = mode);
    await Festival.setIconModeShared(mode);
    await widget.sync.applyIcon(mode);
  }

  void _showPairing() {
    final repo = LaptopConfig(remoteUrl: _remote.text.trim()).repoLabel;
    if (_token.text.trim().isEmpty || repo.split('/').length != 2) {
      setState(() => _error = 'Fill in the notes repo URL and a phone token first');
      return;
    }
    final code = Pairing(repo, _branch.text.trim(), _token.text.trim()).toUri().toString();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan with your phone'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(data: code, size: 260),
              ),
              const SizedBox(height: 16),
              const Text('In the phone app: Settings → Scan pairing code. '
                  'The code contains your token, so close this when done.'),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _form,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Section(
                  title: 'SYNC FOLDER',
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _vault,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Sync folder',
                        helperText: 'Open ${_vault.text.isEmpty ? '<folder>' : _vault.text}'
                            '\\obsidian-notes as your vault in Obsidian',
                        prefixIcon: const Icon(Icons.folder_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Browse',
                          icon: const Icon(Icons.folder_open_rounded),
                          onPressed: _pickVault,
                        ),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                Section(
                  title: 'GITHUB',
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _remote,
                      decoration: const InputDecoration(
                        labelText: 'Notes repo URL',
                        hintText: 'git@github.com:you/obsidian-notes.git',
                        helperText: 'Uses your existing git login (SSH key or Git Credential Manager)',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _branch,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        prefixIcon: Icon(Icons.alt_route_rounded),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                Section(
                  title: 'THIS PC',
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _device,
                      decoration: const InputDecoration(
                        labelText: 'Device name',
                        helperText: 'Starts every commit from this PC, e.g. "laptop: 2 added"',
                        prefixIcon: Icon(Icons.laptop_rounded),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                Section(
                  title: 'TIMING',
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    Text('Upload after you stop typing for ${_debounce}s',
                        style: theme.textTheme.titleMedium),
                    Slider(
                      value: _debounce.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${_debounce}s',
                      onChanged: (v) => setState(() => _debounce = v.round()),
                    ),
                    Text('Check for phone changes every ${_poll ~/ 60} min',
                        style: theme.textTheme.titleMedium),
                    Slider(
                      value: _poll.toDouble(),
                      min: 60,
                      max: 900,
                      divisions: 14,
                      label: '${_poll ~/ 60} min',
                      onChanged: (v) => setState(() => _poll = v.round()),
                    ),
                  ],
                ),
                Section(
                  title: 'PAIR YOUR PHONE',
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _token,
                      obscureText: !_showToken,
                      decoration: InputDecoration(
                        labelText: 'Token for the phone',
                        helperText: 'Fine-grained token · Contents: read & write on the notes repo. '
                            'Kept in Windows Credential Manager.',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_showToken
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded),
                          onPressed: () => setState(() => _showToken = !_showToken),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _showPairing,
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Show pairing code'),
                      ),
                    ),
                  ],
                ),
                const ThemePicker(),
                Section(
                  title: 'APP ICON',
                  children: [
                    for (final m in Festival.iconModes.entries)
                      RadioListTile<String>(
                        value: m.key,
                        // ignore: deprecated_member_use
                        groupValue: _iconMode == 'mono' ? 'mono' : 'auto',
                        // ignore: deprecated_member_use
                        onChanged: (v) => _setIconMode(v!),
                        title: Text(m.value.$1),
                        subtitle: Text(m.key == 'auto'
                            ? 'Colourful. On the phone it also changes for festivals'
                            : m.value.$2),
                      ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text("Couldn't connect the vault: $_error",
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          // heightFactor 1: a bare Align in bottomNavigationBar takes the whole screen height.
          child: Align(
            alignment: Alignment.centerRight,
            heightFactor: 1,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Connecting…' : 'Save'),
            ),
          ),
        ),
      ),
    );
  }
}
