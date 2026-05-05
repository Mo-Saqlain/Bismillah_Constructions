import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mongo_dart/mongo_dart.dart' as mg;
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../db/local_db.dart';
import '../repositories/entity_repository.dart';

/// Cloud backup state for the UI.
enum CloudBackupState { idle, uploading, downloading, error, offline, disabled }

class CloudBackupStatus {
  final CloudBackupState state;
  final String? message;
  final DateTime? lastUploadAt;
  final int? snapshotCount;

  const CloudBackupStatus({
    required this.state,
    this.message,
    this.lastUploadAt,
    this.snapshotCount,
  });

  static const initial = CloudBackupStatus(state: CloudBackupState.idle);
}

/// Lightweight DTO describing a cloud snapshot.
class CloudBackup {
  final String id;
  final DateTime createdAt;
  final int sizeBytes;
  final String? sha1Hex;
  final String deviceId;
  final String? appVersion;

  CloudBackup({
    required this.id,
    required this.createdAt,
    required this.sizeBytes,
    required this.deviceId,
    this.sha1Hex,
    this.appVersion,
  });
}

/// Pushes the SQLite database file to MongoDB whenever the device is online.
///
/// Design parallels [SyncService]: local DB is the source of truth, the cloud
/// is a backup target. Each successful local backup is uploaded as a single
/// BSON document with the raw .db bytes (capped at 15MB to stay under Mongo's
/// 16MB BSON limit). A `latest_<deviceId>` pointer document is upserted to
/// support fast restore. Per-device retention keeps the last 20 snapshots.
class MongoBackupService {
  MongoBackupService(this._entityRepo);
  final EntityRepository _entityRepo;

  static const _collection = 'db_snapshots';
  static const _maxDocBytes = 15 * 1024 * 1024;
  static const _retainPerDevice = 20;
  static const _appVersion = '5.6';

  final _statusCtrl = StreamController<CloudBackupStatus>.broadcast();
  Stream<CloudBackupStatus> get status => _statusCtrl.stream;
  CloudBackupStatus _last = CloudBackupStatus.initial;

  StreamSubscription? _connSub;
  Timer? _debouncer;
  bool _busy = false;

  // ---- Lifecycle ----

  void start() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(uploadLatestIfDue());
    });
    // Try once on start so a fresh boot pushes the latest local state.
    unawaited(uploadLatestIfDue());
  }

  void dispose() {
    _connSub?.cancel();
    _debouncer?.cancel();
    _statusCtrl.close();
  }

  /// Counts how many times the debounced timer has actually fired (i.e. how
  /// many uploads were attempted). Test-only — used to verify that bursts of
  /// commits collapse to one upload.
  @visibleForTesting
  int debouncedFireCount = 0;

  /// Debounced trigger for callers that fire on every transaction commit.
  /// A burst of writes collapses to a single upload after [debounce] of quiet.
  void scheduleUpload({Duration debounce = const Duration(seconds: 5)}) {
    _debouncer?.cancel();
    _debouncer = Timer(debounce, () {
      debouncedFireCount++;
      unawaited(uploadLatestIfDue());
    });
  }

  // ---- Configuration ----
  //
  // The connection details are now hardcoded in [MongoConfig]. This service
  // reads from there directly — no in-app configuration UI.

  bool isConfigured() => MongoConfig.configured;

  String getUri() => MongoConfig.uri;
  String getDbName() => MongoConfig.dbName;

  Future<String> getDeviceId() async {
    var id = await _entityRepo.getSetting(SettingsKeys.deviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _entityRepo.setSetting(SettingsKeys.deviceId, id);
    }
    return id;
  }

  Future<DateTime?> lastCloudBackupAt() async {
    final s = await _entityRepo.getSetting(SettingsKeys.lastCloudBackupAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  // ---- Connectivity helpers ----

  Future<bool> _isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Quick handshake to validate the configured URI. Does not touch the
  /// snapshot collection.
  Future<({bool ok, String message})> testConnection() async {
    if (!isConfigured()) {
      return (ok: false, message: 'MongoConfig.uri is unset / placeholder');
    }
    final resolved = _resolveUri(getUri(), getDbName());
    mg.Db? db;
    try {
      db = await mg.Db.create(resolved);
      await db.open();
      // Force a server roundtrip.
      final stats = await db.serverStatus();
      final host = stats['host']?.toString() ?? 'unknown';
      return (ok: true, message: 'Connected to $host');
    } catch (e) {
      return (ok: false, message: e.toString());
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  // ---- Upload ----

  /// Conditional upload: only runs when configured + online + not busy.
  Future<bool> uploadLatestIfDue() async {
    if (_busy) return false;
    if (!isConfigured()) {
      _emit(const CloudBackupStatus(
          state: CloudBackupState.disabled,
          message:
              'Cloud backup not configured (set MongoConfig.uri or pass --dart-define=MONGO_URI=...)'));
      return false;
    }
    if (!await _isOnline()) {
      _emit(CloudBackupStatus(
          state: CloudBackupState.offline,
          lastUploadAt: _last.lastUploadAt));
      return false;
    }
    return uploadLatest();
  }

  /// Force an upload (the configured/online checks are still applied because
  /// the upload can't physically happen without them).
  Future<bool> uploadLatest({bool force = false}) async {
    if (_busy) return false;
    _busy = true;
    try {
      if (!isConfigured()) {
        _emit(const CloudBackupStatus(
            state: CloudBackupState.disabled,
            message: 'No MongoConfig.uri configured'));
        return false;
      }
      final dbPath = LocalDb.instance.dbPath;
      if (dbPath == null) {
        _emit(const CloudBackupStatus(
            state: CloudBackupState.error, message: 'Local DB not open'));
        return false;
      }
      final src = File(dbPath);
      if (!await src.exists()) {
        _emit(const CloudBackupStatus(
            state: CloudBackupState.error,
            message: 'Local DB file missing'));
        return false;
      }
      if (!await _isOnline()) {
        _emit(const CloudBackupStatus(state: CloudBackupState.offline));
        return false;
      }

      _emit(const CloudBackupStatus(state: CloudBackupState.uploading));

      final bytes = await src.readAsBytes();
      if (bytes.length > _maxDocBytes) {
        _emit(CloudBackupStatus(
          state: CloudBackupState.error,
          message:
              'DB is ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB '
              '— exceeds 15MB cloud limit. Use Export / Share instead.',
        ));
        return false;
      }
      final hash = sha1.convert(bytes).toString();
      final deviceId = await getDeviceId();
      final resolved = _resolveUri(getUri(), getDbName());
      final now = DateTime.now().toUtc();

      mg.Db? db;
      try {
        db = await mg.Db.create(resolved);
        await db.open();
        final col = db.collection(_collection);

        // 1. Insert a new immutable snapshot document. Mongo auto-assigns _id.
        await col.insertOne({
          'deviceId': deviceId,
          'kind': 'snapshot',
          'createdAt': now,
          'sizeBytes': bytes.length,
          'sha1': hash,
          'appVersion': _appVersion,
          'data': mg.BsonBinary.from(bytes),
        });

        // 2. Upsert per-device "latest" pointer for fast restore.
        await col.updateOne(
          mg.where.eq('_id', 'latest_$deviceId'),
          mg.modify
              .set('deviceId', deviceId)
              .set('kind', 'latest')
              .set('createdAt', now)
              .set('sizeBytes', bytes.length)
              .set('sha1', hash)
              .set('appVersion', _appVersion)
              .set('data', mg.BsonBinary.from(bytes)),
          upsert: true,
        );

        // 3. Retention: keep newest N snapshots per device.
        final stale = await col
            .find(mg.where
                .eq('deviceId', deviceId)
                .eq('kind', 'snapshot')
                .sortBy('createdAt', descending: true)
                .skip(_retainPerDevice))
            .toList();
        for (final d in stale) {
          final id = d['_id'];
          if (id != null) {
            await col.deleteOne(mg.where.eq('_id', id));
          }
        }
      } finally {
        try {
          await db?.close();
        } catch (_) {}
      }

      await _entityRepo.setSetting(
          SettingsKeys.lastCloudBackupAt, now.toIso8601String());
      _emit(CloudBackupStatus(
          state: CloudBackupState.idle, lastUploadAt: now));
      return true;
    } catch (e) {
      _emit(CloudBackupStatus(
          state: CloudBackupState.error, message: e.toString()));
      return false;
    } finally {
      _busy = false;
    }
  }

  // ---- Listing & download ----

  Future<List<CloudBackup>> listBackups({int limit = 50}) async {
    if (!isConfigured()) return const [];
    final deviceId = await getDeviceId();
    final resolved = _resolveUri(getUri(), getDbName());

    mg.Db? db;
    try {
      db = await mg.Db.create(resolved);
      await db.open();
      final col = db.collection(_collection);
      final docs = await col
          .find(mg.where
              .eq('deviceId', deviceId)
              .eq('kind', 'snapshot')
              .sortBy('createdAt', descending: true)
              .limit(limit))
          .toList();
      return docs.map(_docToBackup).toList();
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  /// Download the newest snapshot (or the explicit `snapshotId` if given) to
  /// `destPath`. Returns true on success. The caller is responsible for
  /// importing the file back into the local DB (use [BackupService.importBackup]).
  Future<bool> downloadTo(String destPath, {String? snapshotId}) async {
    if (_busy) return false;
    _busy = true;
    try {
      if (!isConfigured()) {
        _emit(const CloudBackupStatus(
            state: CloudBackupState.disabled,
            message: 'No MongoConfig.uri configured'));
        return false;
      }
      if (!await _isOnline()) {
        _emit(const CloudBackupStatus(state: CloudBackupState.offline));
        return false;
      }
      _emit(const CloudBackupStatus(state: CloudBackupState.downloading));

      final deviceId = await getDeviceId();
      final resolved = _resolveUri(getUri(), getDbName());

      mg.Db? db;
      try {
        db = await mg.Db.create(resolved);
        await db.open();
        final col = db.collection(_collection);

        Map<String, dynamic>? doc;
        if (snapshotId != null) {
          doc = await col.findOne(mg.where.eq('_id', snapshotId));
        } else {
          doc = await col.findOne(mg.where.eq('_id', 'latest_$deviceId'));
          // Fall back to newest snapshot from the same device if no pointer.
          doc ??= await col.findOne(mg.where
              .eq('deviceId', deviceId)
              .eq('kind', 'snapshot')
              .sortBy('createdAt', descending: true));
        }
        if (doc == null) {
          _emit(const CloudBackupStatus(
              state: CloudBackupState.error,
              message: 'No cloud snapshot found for this device'));
          return false;
        }
        final bytes = _extractBytes(doc['data']);
        if (bytes == null || bytes.isEmpty) {
          _emit(const CloudBackupStatus(
              state: CloudBackupState.error,
              message: 'Snapshot payload missing or unreadable'));
          return false;
        }
        await File(destPath).writeAsBytes(bytes, flush: true);
        _emit(CloudBackupStatus(
            state: CloudBackupState.idle,
            lastUploadAt: _last.lastUploadAt));
        return true;
      } finally {
        try {
          await db?.close();
        } catch (_) {}
      }
    } catch (e) {
      _emit(CloudBackupStatus(
          state: CloudBackupState.error, message: e.toString()));
      return false;
    } finally {
      _busy = false;
    }
  }

  // ---- Internals ----

  void _emit(CloudBackupStatus s) {
    _last = s;
    _statusCtrl.add(s);
  }

  List<int>? _extractBytes(dynamic data) {
    if (data == null) return null;
    try {
      // mongo_dart returns binary as BsonBinary with a `byteList` getter.
      final dyn = data as dynamic;
      final bl = dyn.byteList;
      if (bl is List<int>) return bl;
    } catch (_) {/* not a BsonBinary */}
    if (data is List<int>) return data;
    return null;
  }

  CloudBackup _docToBackup(Map<String, dynamic> d) {
    final raw = d['createdAt'];
    DateTime ts;
    if (raw is DateTime) {
      ts = raw;
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now().toUtc();
    } else {
      ts = DateTime.now().toUtc();
    }
    return CloudBackup(
      id: d['_id']?.toString() ?? '',
      createdAt: ts,
      sizeBytes: (d['sizeBytes'] as num?)?.toInt() ?? 0,
      sha1Hex: d['sha1'] as String?,
      deviceId: (d['deviceId'] as String?) ?? '',
      appVersion: d['appVersion'] as String?,
    );
  }

  /// Append the database name onto the URI when it is not already present
  /// (mongo_dart selects a database from the URI path segment).
  String _resolveUri(String uri, String dbName) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.path.isEmpty || parsed.path == '/') {
        final sep = uri.endsWith('/') ? '' : '/';
        return '$uri$sep$dbName';
      }
      return uri;
    } catch (_) {
      return uri;
    }
  }
}
