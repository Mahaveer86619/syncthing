import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../festival.dart';
import '../pairing.dart';
import '../schedule.dart';
import '../vaults.dart';
import 'theme_choice.dart';
import 'widgets.dart';

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
  bool _showToken = false;
  bool _loaded = false;
  List<String> _vaults = [];
  String _iconMode = 'auto';

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
    _iconMode = await Festival.iconMode();
    if (mounted) setState(() => _loaded = true);
    // Walking shared storage can take seconds; the form is usable meanwhile.
    if (_storageGranted) await _detectVaults();
  }

  Future<void> _detectVaults() async {
    final vaults = await findVaults();
    final current = _vault.text.trim();
    if (current.isNotEmpty && !isVault(current)) {
      _vault.text = await resolveVault(current);
    }
    if (_vault.text.trim().isEmpty && vaults.isNotEmpty) _vault.text = vaults.first;
    if (mounted) setState(() => _vaults = vaults);
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
    if (granted) await _detectVaults();
  }

  // Without this, Doze and vendor battery savers can delay background syncs by hours.
  Future<void> _requestBattery() async {
    final granted = await Permission.ignoreBatteryOptimizations.request().isGranted;
    if (mounted) setState(() => _batteryUnrestricted = granted);
  }

  Future<void> _pickVault() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Obsidian vault folder');
    if (path == null) return;
    final resolved = await resolveVault(path);
    setState(() => _vault.text = resolved);
  }

  Future<void> _setIconMode(String mode) async {
    setState(() => _iconMode = mode);
    await Festival.setIconMode(mode);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The home-screen icon updates when you leave the app')),
    );
  }

  Future<void> _scanPairing() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pairing = Pairing.parse(await Festival.scanQr());
      if (pairing == null) return;
      setState(() {
        _repo.text = pairing.repo;
        _branch.text = pairing.branch;
        _token.text = pairing.token;
      });
      messenger.showSnackBar(SnackBar(content: Text('Paired with ${pairing.repo}. Check the vault, then Save')));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open the scanner. Is Google Play Services up to date?")));
    }
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
    if (mounted) Navigator.of(context).pop(true);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: CustomScrollView(
                slivers: [
                  const SliverAppBar.large(title: Text('Settings')),
                  SliverList.list(children: [
                    Section(
                      title: 'GITHUB',
                      padding: const EdgeInsets.all(16),
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _scanPairing,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Scan pairing code'),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                          child: Text(
                            'Open Settings → Pair your phone in the Windows app and scan its code, '
                            'or fill these in yourself.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextFormField(
                          controller: _repo,
                          decoration: const InputDecoration(
                            labelText: 'Notes repo',
                            hintText: 'owner/repo',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          validator: (v) =>
                              SyncConfig.normaliseRepo(v ?? '').split('/').length == 2
                                  ? null
                                  : 'Use owner/repo',
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
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _token,
                          obscureText: !_showToken,
                          decoration: InputDecoration(
                            labelText: 'Access token',
                            helperText: 'Fine-grained token · Contents: read & write on this repo',
                            prefixIcon: const Icon(Icons.key_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_showToken
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded),
                              onPressed: () => setState(() => _showToken = !_showToken),
                            ),
                          ),
                          validator: _required,
                        ),
                      ],
                    ),
                    Section(
                      title: 'VAULT',
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_vaults.isNotEmpty) ...[
                          Text('Found on this phone',
                              style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final v in _vaults)
                                ChoiceChip(
                                  avatar: const Icon(Icons.auto_stories_outlined, size: 18),
                                  label: Text(v.split('/').last),
                                  selected: _vault.text.trim() == v,
                                  onSelected: (_) => setState(() => _vault.text = v),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _vault,
                          decoration: InputDecoration(
                            labelText: 'Vault folder',
                            prefixIcon: const Icon(Icons.folder_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'Browse',
                              icon: const Icon(Icons.folder_open_rounded),
                              onPressed: _pickVault,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (_storageGranted && !isVault(v.trim())) {
                              return 'Not an Obsidian vault (no .obsidian folder inside)';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                    Section(
                      title: 'THIS PHONE',
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextFormField(
                          controller: _device,
                          decoration: const InputDecoration(
                            labelText: 'Device name',
                            helperText: 'Starts every commit from this phone, e.g. "phone: 2 added"',
                            prefixIcon: Icon(Icons.smartphone_rounded),
                          ),
                          validator: _required,
                        ),
                      ],
                    ),
                    Section(
                      title: 'KEEP SYNCING RELIABLY',
                      children: [
                        _PermissionTile(
                          icon: Icons.folder_special_rounded,
                          title: 'Storage access',
                          granted: _storageGranted,
                          grantedText: 'Can read and write your vault',
                          neededText: 'Needed to read and write your vault',
                          onGrant: _requestStorage,
                        ),
                        _PermissionTile(
                          icon: Icons.battery_charging_full_rounded,
                          title: 'Unrestricted battery',
                          granted: _batteryUnrestricted,
                          grantedText: 'Background syncs run on time',
                          neededText: "So Android doesn't postpone auto sync",
                          onGrant: _requestBattery,
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const TonalIcon(Icons.rocket_launch_rounded),
                          title: Text('Auto-start',
                              style: Theme.of(context).textTheme.titleMedium),
                          subtitle: const Text(
                              'Some phones (Infinix, Xiaomi, Oppo, Vivo) stop background syncing when '
                              'you swipe the app away. Allow Syncthing to auto-start there, and lock it '
                              'in Recents.'),
                          isThreeLine: true,
                          trailing: FilledButton.tonal(
                            onPressed: Festival.openAutoStart,
                            child: const Text('Open'),
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
                            subtitle: Text(m.value.$2),
                          ),
                      ],
                    ),
                  ]),
                ],
              ),
            ),
      bottomNavigationBar: !_loaded
          ? null
          : SafeArea(
              child: Container(
                color: scheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                ),
              ),
            ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.granted,
    required this.grantedText,
    required this.neededText,
    required this.onGrant,
  });

  final IconData icon;
  final String title, grantedText, neededText;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: TonalIcon(
        granted ? Icons.check_rounded : icon,
        color: granted ? scheme.primaryContainer : scheme.errorContainer,
        onColor: granted ? scheme.onPrimaryContainer : scheme.onErrorContainer,
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(granted ? grantedText : neededText),
      trailing: granted ? null : FilledButton.tonal(onPressed: onGrant, child: const Text('Allow')),
    );
  }
}
