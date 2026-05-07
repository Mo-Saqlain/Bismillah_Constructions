import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_restart.dart';
import '../../data/db/local_db.dart';
import '../../providers/providers.dart';
import '../home/home_screen.dart';

/// Thin startup gate that sits in front of [HomeScreen].
///
/// On Android the primary database now lives in external app-scoped storage
/// (Bismillah_Data folder) which survives uninstall on most devices, so no
/// "restore from backup?" dialog is needed.
///
/// The only job of this widget is a one-time silent migration: if the external
/// DB is still empty (first run after an app update or a device with no
/// external storage fallback) AND the old internal database file has data,
/// copy it to the new location before proceeding.  The user never sees a
/// dialog — the app just opens.
class RestoreGateway extends ConsumerStatefulWidget {
  const RestoreGateway({super.key});

  @override
  ConsumerState<RestoreGateway> createState() => _RestoreGatewayState();
}

class _RestoreGatewayState extends ConsumerState<RestoreGateway> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  Future<void> _startup() async {
    try {
      // Open the DB (now from external persistent path on Android).
      final db = await ref.read(dbProvider.future);

      final projCount =
          ((await db.rawQuery('SELECT COUNT(*) AS c FROM projects'))
                  .first['c'] as int?) ??
              0;
      final entryCount =
          ((await db.rawQuery('SELECT COUNT(*) AS c FROM journal_entries'))
                  .first['c'] as int?) ??
              0;

      if (projCount > 0 || entryCount > 0) {
        // DB already has data — normal cold start.
        if (mounted) setState(() => _ready = true);
        return;
      }

      // External DB is empty. Check whether the old internal-storage DB has
      // data that should be migrated silently (first run after update, or
      // fallback path is the same as legacy path).
      if (Platform.isAndroid) {
        await _tryMigrateFromLegacy();
        return; // either restartApp() or _ready = true happens inside
      }
    } catch (_) {
      // Any error — just open HomeScreen with whatever data exists.
    }

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _tryMigrateFromLegacy() async {
    try {
      final oldPath = await LocalDb.legacyInternalPath();
      final newPath = LocalDb.instance.dbPath;

      // If paths are the same, external storage wasn't available and we fell
      // back to the same directory — nothing to migrate.
      if (newPath == null || newPath == oldPath) {
        if (mounted) setState(() => _ready = true);
        return;
      }

      final oldFile = File(oldPath);
      // Only migrate if the legacy file actually exists and has real content
      // (empty SQLite headers are < 4 KB).
      if (!await oldFile.exists() || await oldFile.length() < 4096) {
        if (mounted) setState(() => _ready = true);
        return;
      }

      // Close the empty external DB, copy the legacy file over it, reopen.
      await LocalDb.instance.reinitialize();
      await oldFile.copy(newPath);
      // Rebuild the entire ProviderScope so every provider reopens the
      // newly-populated DB from scratch.
      restartApp();
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const HomeScreen();
  }
}
