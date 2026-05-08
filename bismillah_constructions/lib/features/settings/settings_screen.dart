import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/formatters.dart';
import '../../providers/providers.dart';
import 'backups_list_screen.dart';
import 'change_log_screen.dart';
import 'recent_errors_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  DateTime? _lastBackup;
  String? _backupFolder;
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshBackupTime();
    _resolveBackupFolder();
  }

  Future<void> _refreshBackupTime() async {
    final svc = await ref.read(backupServiceProvider.future);
    final t = await svc.lastBackupAt();
    if (!mounted) return;
    setState(() => _lastBackup = t);
  }

  /// Mirrors `BackupService.backupDirectory()` so the user can see (and copy)
  /// where their backups are written.
  Future<void> _resolveBackupFolder() async {
    Directory? base;
    try {
      if (Platform.isAndroid) {
        final dirs = await getExternalStorageDirectories(
            type: StorageDirectory.documents);
        if (dirs != null && dirs.isNotEmpty) base = dirs.first;
      }
      base ??= await getApplicationDocumentsDirectory();
    } catch (_) {/* fall through */}
    if (base == null) return;
    if (!mounted) return;
    setState(() => _backupFolder = p.join(base!.path, 'Bismillah_Backups'));
  }

  Future<void> _importBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // FileType.any avoids Android SAF rejecting the non-standard `.db`
      // MIME type (which silently throws on some devices and never opens
      // the picker). We validate the extension ourselves below.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select a Bismillah .db backup',
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Could not read file path — try copying the backup to internal storage first.')));
        return;
      }
      final lower = picked.name.toLowerCase();
      if (!lower.endsWith('.db')) {
        messenger.showSnackBar(SnackBar(
            content: Text(
                'Not a .db backup file: ${picked.name}. Pick a file ending in .db.')));
        return;
      }

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber,
              color: Theme.of(ctx).colorScheme.error, size: 36),
          title: const Text('Replace your current database?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Importing "${picked.name}" will:'),
                const SizedBox(height: 12),
                const _BulletLine(
                    'WIPE every transaction, project, supplier, bank, '
                    'wallet, material type and setting that is currently '
                    'in this app.'),
                const _BulletLine(
                    'REPLACE all of it with whatever the picked .db file '
                    'contains. The import is a full overwrite, not a '
                    'merge — anything not in the picked file is gone.'),
                const _BulletLine(
                    'Save your existing database as a "<dbfile>.before_import" '
                    'snapshot first, so you can use Settings → "Undo last '
                    'import" to roll back if you change your mind.'),
                const _BulletLine(
                    'Require an app restart afterwards to load the new data.'),
                const SizedBox(height: 12),
                Text(
                  'Only proceed if you trust this .db file and you have '
                  'already exported anything you might want to keep from '
                  'the current install.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace database')),
          ],
        ),
      );
      if (confirm != true) return;

      setState(() => _backupBusy = true);
      final backup = await ref.read(backupServiceProvider.future);
      final err = await backup.importBackup(path);
      if (!mounted) return;
      setState(() => _backupBusy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Imported. Restart the app to load the new database.'
            : 'Import failed: $err'),
        duration: const Duration(seconds: 6),
      ));
    } catch (e, st) {
      debugPrint('Import backup failed: $e\n$st');
      if (!mounted) return;
      setState(() => _backupBusy = false);
      messenger.showSnackBar(SnackBar(
        content: Text('Import error: $e'),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  Future<void> _runBackupNow() async {
    setState(() => _backupBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final svc = await ref.read(backupServiceProvider.future);
    final ok = await svc.runBackup();
    await _refreshBackupTime();
    if (!mounted) return;
    setState(() => _backupBusy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Backup written to the backup folder'
          : 'Backup failed — check storage permissions / free space'),
    ));
  }

  Future<void> _shareLatestBackup() async {
    setState(() => _backupBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final svc = await ref.read(backupServiceProvider.future);
    final ok = await svc.shareLatestBackup();
    if (!mounted) return;
    setState(() => _backupBusy = false);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No backup available to share — try again')));
    }
  }

  Future<void> _testFolder() async {
    final messenger = ScaffoldMessenger.of(context);
    final svc = await ref.read(backupServiceProvider.future);
    final reason = await svc.testBackupFolder();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(reason == null
          ? 'Backup folder is writable ✓'
          : 'Folder test failed: $reason'),
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _rollbackImport() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo last import?'),
        content: const Text(
            'Restores the database from the snapshot saved before your last import. '
            'The current database will be saved as "<dbfile>.before_rollback" '
            'in case you change your mind. You must restart the app afterwards.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Roll back')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _backupBusy = true);
    final svc = await ref.read(backupServiceProvider.future);
    final err = await svc.rollbackLastImport();
    if (!mounted) return;
    setState(() => _backupBusy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(err ??
          'Rolled back. Restart the app to load the previous database.'),
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);

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
          _SectionTitle('Backup & Export'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Backup folder'),
                  subtitle: Text(
                    _backupFolder ?? 'Resolving…',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: _backupFolder == null
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.bug_report, size: 18),
                            tooltip: 'Test write access',
                            onPressed: _backupBusy ? null : _testFolder,
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Copy path',
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await Clipboard.setData(
                                  ClipboardData(text: _backupFolder!));
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Path copied')),
                              );
                            },
                          ),
                        ]),
                ),
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
                      'Saves to the backup folder above (survives uninstall on Android)'),
                  trailing: _backupBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _backupBusy ? null : _runBackupNow,
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Share latest backup'),
                  subtitle: const Text(
                      'Send the .db file via WhatsApp / Gmail / Drive'),
                  trailing: _backupBusy
                      ? null
                      : const Icon(Icons.chevron_right),
                  onTap: _backupBusy ? null : _shareLatestBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Import backup'),
                  subtitle: const Text(
                      'Pick a .db file and replace the current database'),
                  trailing: _backupBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _backupBusy ? null : _importBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('Backup history'),
                  subtitle: const Text(
                      'Browse, share, restore or delete past backups'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BackupsListScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('Undo last import'),
                  subtitle: const Text(
                      'Roll back to the snapshot saved before your last import'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _backupBusy ? null : _rollbackImport,
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
          Card(
            child: ListTile(
              leading: Icon(Icons.bug_report_outlined,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Recent Errors'),
              subtitle: const Text(
                  'In-app log of framework, async and widget errors '
                  'caught this session.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RecentErrorsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // The launcher icon is the only place the brand mark appears.
          // The footer keeps just the wordmark so the screen still feels
          // signed.
          Center(
            child: Text(
              'Bismillah',
              style: Theme.of(context).textTheme.bodySmall,
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

/// Bullet row used in the Import warning dialog. Pulled out so the dialog
/// stays readable and indents stay consistent across all four bullets.
class _BulletLine extends StatelessWidget {
  const _BulletLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
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
