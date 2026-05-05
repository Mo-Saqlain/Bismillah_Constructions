import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../db/local_db.dart';
import '../repositories/entity_repository.dart';
import 'mongo_backup_service.dart';

/// Backs up the SQLite database to a user-visible Documents folder so the
/// data survives app uninstall (Android: external Documents). Trigger:
/// silent on cold-boot if last backup is older than 6 hours (spec section 5).
///
/// When a [MongoBackupService] is attached, every successful local backup is
/// also pushed to the cloud (best-effort — never blocks or fails the local op).
class BackupService {
  BackupService(this._entityRepo, {MongoBackupService? cloud}) : _cloud = cloud;
  final EntityRepository _entityRepo;
  final MongoBackupService? _cloud;

  static const _folderName = 'Bismillah_Backups';
  static const _backupInterval = Duration(hours: 6);

  /// Cold-boot trigger: only runs if last backup older than 6h.
  Future<bool> maybeRunSilentBackup() async {
    final lastStr =
        await _entityRepo.getSetting(SettingsKeys.lastBackupAt);
    final last = lastStr == null ? null : DateTime.tryParse(lastStr);
    final now = DateTime.now().toUtc();
    if (last != null && now.difference(last) < _backupInterval) {
      return false;
    }
    return runBackup();
  }

  /// Manual or scheduled backup. Returns true if backup file written.
  Future<bool> runBackup() async {
    try {
      final dir = await _backupDirectory();
      if (dir == null) return false;
      final dbPath = LocalDb.instance.dbPath;
      if (dbPath == null) return false;
      final src = File(dbPath);
      if (!await src.exists()) return false;

      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final destPath = p.join(dir.path, 'solo_con_$stamp.db');
      await src.copy(destPath);

      // Also keep a "latest" copy for easy restore.
      final latest = File(p.join(dir.path, 'solo_con_latest.db'));
      await src.copy(latest.path);

      await _entityRepo.setSetting(
        SettingsKeys.lastBackupAt,
        DateTime.now().toUtc().toIso8601String(),
      );

      // Best-effort cloud push: never block or fail the local backup result.
      final cloud = _cloud;
      if (cloud != null) {
        unawaited(cloud.uploadLatestIfDue());
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Share the latest backup file via system share sheet (single-file export).
  Future<void> shareBackup() async {
    final dir = await _backupDirectory();
    if (dir == null) return;
    final latest = File(p.join(dir.path, 'solo_con_latest.db'));
    if (!await latest.exists()) {
      // Run a fresh backup first.
      await runBackup();
    }
    if (await latest.exists()) {
      await Share.shareXFiles([XFile(latest.path)],
          text: 'Bismillah Constructions ERP backup');
    }
  }

  /// Import a database file (replacing the current one). Caller must restart.
  Future<bool> importBackup(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) return false;
    final dbPath = LocalDb.instance.dbPath;
    if (dbPath == null) return false;
    try {
      // Make a safety copy of current DB before overwrite.
      final cur = File(dbPath);
      if (await cur.exists()) {
        await cur.copy('$dbPath.before_import');
      }
      await src.copy(dbPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<DateTime?> lastBackupAt() async {
    final s = await _entityRepo.getSetting(SettingsKeys.lastBackupAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<Directory?> _backupDirectory() async {
    Directory? base;
    try {
      // Android external Documents (survives uninstall on most setups).
      if (Platform.isAndroid) {
        final dirs = await getExternalStorageDirectories(
            type: StorageDirectory.documents);
        if (dirs != null && dirs.isNotEmpty) base = dirs.first;
      }
      // Fallback: app documents directory.
      base ??= await getApplicationDocumentsDirectory();
    } catch (_) {
      try {
        base = await getApplicationDocumentsDirectory();
      } catch (_) {
        return null;
      }
    }
    final folder = Directory(p.join(base.path, _folderName));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }
}
