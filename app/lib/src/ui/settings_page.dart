import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../schedule.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form = GlobalKey<FormState>();
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _vault = TextEditingController();
  final _device = TextEditingController();
  final _token = TextEditingController();
  bool _autoSync = true;
  bool _storageGranted = false;
  bool _batteryUnrestricted = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await SyncConfig.load();
    _repo.text = c.repo;
    _branch.text = c.branch;
    _vault.text = c.vaultPath;
    _device.text = c.deviceName;
    _token.text = c.token;
    _autoSync = c.autoSync;
    _storageGranted = await _hasStorageAccess();
    _batteryUnrestricted = await Permission.ignoreBatteryOptimizations.isGranted;
    if (mounted) setState(() => _loaded = true);
  }

  // Obsidian vaults live in shared storage, which plain file IO can only reach with "All files access".
  Future<bool> _hasStorageAccess() async =>
      await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted;

  Future<void> _requestStorage() async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      await Permission.storage.request();
    }
    final granted = await _hasStorageAccess();
    if (mounted) setState(() => _storageGranted = granted);
  }

  // Without this, Doze and vendor battery savers can delay background syncs by hours.
  Future<void> _requestBattery() async {
    final granted = await Permission.ignoreBatteryOptimizations.request().isGranted;
    if (mounted) setState(() => _batteryUnrestricted = granted);
  }

  Future<void> _pickVault() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Obsidian vault folder');
    if (path != null) _vault.text = path;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await SyncConfig(
      repo: _repo.text,
      branch: _branch.text,
      vaultPath: _vault.text,
      deviceName: _device.text,
      token: _token.text,
      autoSync: _autoSync,
    ).save();
    await applySchedule(_autoSync);
    if (mounted) Navigator.of(context).pop();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _repo,
                    decoration: const InputDecoration(
                      labelText: 'Notes repo',
                      hintText: 'owner/repo or GitHub URL',
                    ),
                    validator: (v) => SyncConfig.normaliseRepo(v ?? '').split('/').length == 2
                        ? null
                        : 'Use owner/repo',
                  ),
                  TextFormField(
                    controller: _branch,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'GitHub token',
                      helperText: 'Fine-grained token: Contents read/write on this repo only',
                    ),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _vault,
                    decoration: InputDecoration(
                      labelText: 'Vault folder',
                      hintText: '/storage/emulated/0/Documents/MyVault',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: _pickVault,
                      ),
                    ),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _device,
                    decoration: const InputDecoration(
                      labelText: 'Device name',
                      helperText: 'Shown in commit messages',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_storageGranted ? Icons.check_circle : Icons.warning_amber),
                    title: const Text('Storage access'),
                    subtitle: Text(_storageGranted
                        ? 'Granted'
                        : 'Needed to read and write the vault folder'),
                    trailing: _storageGranted
                        ? null
                        : TextButton(onPressed: _requestStorage, child: const Text('Grant')),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_batteryUnrestricted ? Icons.check_circle : Icons.battery_alert),
                    title: const Text('Battery: unrestricted'),
                    subtitle: Text(_batteryUnrestricted
                        ? 'Background syncs run on time'
                        : "Recommended so Android doesn't postpone auto sync"),
                    trailing: _batteryUnrestricted
                        ? null
                        : TextButton(onPressed: _requestBattery, child: const Text('Allow')),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ),
    );
  }
}
