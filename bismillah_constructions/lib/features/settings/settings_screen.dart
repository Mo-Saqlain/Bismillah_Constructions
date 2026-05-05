import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/services/mongo_backup_service.dart';
import '../../providers/providers.dart';
import '../parties/banks_screen.dart';
import 'change_log_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  DateTime? _lastBackup;
  DateTime? _lastCloudBackup;
  bool _backupBusy = false;
  bool _cloudBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshBackupTime();
    _refreshCloudState();
  }

  Future<void> _refreshBackupTime() async {
    final svc = await ref.read(backupServiceProvider.future);
    final t = await svc.lastBackupAt();
    if (!mounted) return;
    setState(() => _lastBackup = t);
  }

  Future<void> _refreshCloudState() async {
    final svc = await ref.read(mongoBackupServiceProvider.future);
    final last = await svc.lastCloudBackupAt();
    if (!mounted) return;
    setState(() => _lastCloudBackup = last);
  }

  Future<void> _runCloudBackupNow() async {
    setState(() => _cloudBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final svc = await ref.read(mongoBackupServiceProvider.future);
    final ok = await svc.uploadLatest(force: true);
    await _refreshCloudState();
    if (!mounted) return;
    setState(() => _cloudBusy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Cloud backup uploaded'
          : 'Cloud backup failed — check MongoConfig.uri & connectivity'),
    ));
  }

  Future<void> _testCloudConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    final svc = await ref.read(mongoBackupServiceProvider.future);
    final r = await svc.testConnection();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text('${r.ok ? "OK" : "Failed"}: ${r.message}')));
  }

  Future<void> _restoreFromCloud() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from cloud?'),
        content: const Text(
            'This overwrites your current local database with the latest '
            'cloud snapshot for this device. The current DB is preserved as '
            '<dbfile>.before_import. Restart the app afterwards.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _cloudBusy = true);
    final cloud = await ref.read(mongoBackupServiceProvider.future);
    final backup = await ref.read(backupServiceProvider.future);

    final tmpDir = await getTemporaryDirectory();
    if (!mounted) return;
    final tmpPath = p.join(tmpDir.path,
        'cloud_restore_${DateTime.now().millisecondsSinceEpoch}.db');
    final downloaded = await cloud.downloadTo(tmpPath);
    if (!downloaded) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Cloud download failed — no snapshot or no network')));
      return;
    }
    final imported = await backup.importBackup(tmpPath);
    try {
      await File(tmpPath).delete();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _cloudBusy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(imported
          ? 'Cloud snapshot restored — restart the app to load it'
          : 'Restore failed — local DB is unchanged'),
    ));
  }

  String _cloudStatusLine(AsyncValue<CloudBackupStatus> async) {
    if (!MongoConfig.configured) {
      return 'MongoConfig.uri not set — edit lib/core/constants.dart';
    }
    final s = async.asData?.value;
    if (s == null) return 'Idle · auto-uploads after every commit';
    return switch (s.state) {
      CloudBackupState.uploading => 'Uploading to MongoDB…',
      CloudBackupState.downloading => 'Downloading from MongoDB…',
      CloudBackupState.offline => 'Offline — will retry when back online',
      CloudBackupState.error =>
        'Last attempt failed: ${s.message ?? "unknown error"}',
      CloudBackupState.disabled => s.message ?? 'Cloud backup disabled',
      CloudBackupState.idle => 'Idle · auto-uploads after every commit',
    };
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final cloudStatus = ref.watch(cloudBackupStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionTitle('Appearance'),
          Card(
            child: Column(
              children: [
                _ThemeOption(
                  label: 'System default',
                  value: ThemeMode.system,
                  current: mode,
                  onSelect: (v) =>
                      ref.read(themeModeProvider.notifier).setMode(v),
                ),
                _ThemeOption(
                  label: 'Light',
                  value: ThemeMode.light,
                  current: mode,
                  onSelect: (v) =>
                      ref.read(themeModeProvider.notifier).setMode(v),
                ),
                _ThemeOption(
                  label: 'Dark',
                  value: ThemeMode.dark,
                  current: mode,
                  onSelect: (v) =>
                      ref.read(themeModeProvider.notifier).setMode(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionTitle('Banks & Wallets'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('Manage banks / wallets'),
              subtitle: const Text(
                  'Define your own bank accounts and digital wallets — each becomes a Pay-From / Receive-Into option'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BanksScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionTitle('Backup & Export'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Last backup'),
                  subtitle: Text(_lastBackup == null
                      ? 'Never'
                      : fmtDateTime(_lastBackup!)),
                ),
                ListTile(
                  leading: const Icon(Icons.backup),
                  title: const Text('Run backup now'),
                  subtitle: const Text(
                      'Saves to /Documents/Bismillah_Backups (survives uninstall on Android)'),
                  trailing: _backupBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _backupBusy
                      ? null
                      : () async {
                          setState(() => _backupBusy = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final svc = await ref
                              .read(backupServiceProvider.future);
                          final ok = await svc.runBackup();
                          await _refreshBackupTime();
                          if (!mounted) return;
                          setState(() => _backupBusy = false);
                          messenger.showSnackBar(
                            SnackBar(
                                content: Text(ok
                                    ? 'Backup written'
                                    : 'Backup failed')),
                          );
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Export / Share latest backup'),
                  subtitle: const Text('Single-file portability for migration'),
                  onTap: () async {
                    final svc =
                        await ref.read(backupServiceProvider.future);
                    await svc.shareBackup();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionTitle('Cloud Backup (MongoDB)'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(MongoConfig.configured
                      ? Icons.cloud_done
                      : Icons.cloud_off),
                  title: const Text('Status'),
                  subtitle: Text(_cloudStatusLine(cloudStatus)),
                ),
                ListTile(
                  leading: const Icon(Icons.history_toggle_off),
                  title: const Text('Last cloud backup'),
                  subtitle: Text(_lastCloudBackup == null
                      ? 'Never'
                      : fmtDateTime(_lastCloudBackup!)),
                ),
                if (MongoConfig.configured) ...[
                  ListTile(
                    leading: const Icon(Icons.network_check),
                    title: const Text('Test connection'),
                    onTap: _testCloudConnection,
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload),
                    title: const Text('Backup to cloud now'),
                    enabled: !_cloudBusy,
                    trailing: _cloudBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _cloudBusy ? null : _runCloudBackupNow,
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_download),
                    title: const Text('Restore from cloud'),
                    enabled: !_cloudBusy,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _cloudBusy ? null : _restoreFromCloud,
                  ),
                ],
                if (!MongoConfig.configured)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      'Edit `lib/core/constants.dart` → MongoConfig._uri to '
                      'paste your Atlas connection string, OR run with '
                      '--dart-define=MONGO_URI=mongodb+srv://user:pass@cluster.../',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionTitle('Audit'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fact_check),
              title: const Text('Change Log'),
              subtitle: const Text(
                  'View all edits/deletes/archives. Export to CSV.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangeLogScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 48),
                const SizedBox(height: 4),
                Text(
                  'Bismillah',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelect,
  });
  final String label;
  final ThemeMode value;
  final ThemeMode current;
  final ValueChanged<ThemeMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return ListTile(
      leading: Icon(selected
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked),
      title: Text(label),
      onTap: () => onSelect(value),
    );
  }
}
