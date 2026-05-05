import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../providers/providers.dart';
import 'change_log_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  DateTime? _lastBackup;
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshBackupTime();
  }

  Future<void> _refreshBackupTime() async {
    final svc = await ref.read(backupServiceProvider.future);
    final t = await svc.lastBackupAt();
    if (!mounted) return;
    setState(() => _lastBackup = t);
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
            child: Text(
              'Bismillah Constructions ERP · v5.6',
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
