import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_restart.dart';
import '../../core/formatters.dart';
import '../../data/db/local_db.dart';
import '../../data/services/backup_service.dart';
import '../../providers/providers.dart';
import '../home/home_screen.dart';

/// Shown once on every cold start instead of [HomeScreen].
///
/// If the database is empty AND a backup file exists in the backup folder,
/// the user is prompted to restore it before the app continues. The prompt
/// only fires when the database is genuinely empty — i.e. right after a
/// fresh install or a full data wipe — so it never interrupts normal use.
///
/// On confirm: closes the in-process (empty) DB, copies the backup file over
/// the DB path, reopens the DB with the restored data, and invalidates all
/// Riverpod providers so every screen picks up the new content.
class RestoreGateway extends ConsumerStatefulWidget {
  const RestoreGateway({super.key});

  @override
  ConsumerState<RestoreGateway> createState() => _RestoreGatewayState();
}

class _RestoreGatewayState extends ConsumerState<RestoreGateway> {
  bool _checked = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoRestore());
  }

  Future<void> _checkAutoRestore() async {
    try {
      final db = await ref.read(dbProvider.future);

      final projResult =
          await db.rawQuery('SELECT COUNT(*) AS c FROM projects');
      final projCount = (projResult.first['c'] as int?) ?? 0;

      final entryResult =
          await db.rawQuery('SELECT COUNT(*) AS c FROM journal_entries');
      final entryCount = (entryResult.first['c'] as int?) ?? 0;

      if (projCount > 0 || entryCount > 0) {
        // Database already has content — nothing to restore.
        if (mounted) setState(() => _checked = true);
        return;
      }

      // Empty DB — look for a backup in the backup folder.
      final backupPath =
          await BackupService.findLatestBackupForAutoRestore();
      if (backupPath == null || !mounted) {
        if (mounted) setState(() => _checked = true);
        return;
      }

      final stat = await File(backupPath).stat();
      final backupDate = fmtDateTime(stat.modified.toLocal());
      final sizeMb = (stat.size / (1024 * 1024)).toStringAsFixed(1);

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore previous data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'A backup from a previous installation was found:'),
              const SizedBox(height: 12),
              Text('Date: $backupDate',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Size: $sizeMb MB'),
              const SizedBox(height: 12),
              const Text(
                  'Restore it now? You can also skip and import it '
                  'manually later from Settings → Import backup.'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Restore')),
          ],
        ),
      );

      if (confirm == true && mounted) {
        setState(() => _restoring = true);
        await _doRestore(backupPath);
      }
    } catch (_) {
      // Any error → proceed to HomeScreen with whatever data exists.
    }

    if (mounted) {
      setState(() {
        _checked = true;
        _restoring = false;
      });
    }
  }

  Future<void> _doRestore(String backupPath) async {
    final dbPath = LocalDb.instance.dbPath;
    if (dbPath == null) return;

    // Close the in-process (empty) DB so sqflite releases the file handle.
    await LocalDb.instance.reinitialize();

    // Overwrite the DB file with the backup.
    await File(backupPath).copy(dbPath);

    // Trigger a full ProviderScope teardown → all providers rebuild from
    // scratch and LocalDb.open() reopens the now-restored file cleanly.
    restartApp();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _restoring) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_restoring) ...[
                const SizedBox(height: 16),
                Text('Restoring backup…',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}
