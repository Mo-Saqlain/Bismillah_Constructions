import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../repositories/ledger_repository.dart';

enum SyncState { idle, syncing, error, offline, disabled }

class SyncStatus {
  final SyncState state;
  final int pending;
  final String? message;
  final DateTime? lastSyncAt;

  const SyncStatus({
    required this.state,
    required this.pending,
    this.message,
    this.lastSyncAt,
  });

  static const initial =
      SyncStatus(state: SyncState.idle, pending: 0);
}

/// Pushes un-synced journal rows to Supabase whenever the device is online.
///
/// The local DB is the source of truth — Supabase is the cloud backup. This
/// service NEVER pulls; the spec is a single-operator app, so there is one
/// writer.
class SyncService {
  SyncService(this._ledger);
  final LedgerRepository _ledger;

  final _statusCtrl = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _statusCtrl.stream;
  SyncStatus _last = SyncStatus.initial;

  StreamSubscription? _connSub;
  Timer? _ticker;

  void start() {
    if (!SupabaseConfig.configured) {
      _emit(const SyncStatus(state: SyncState.disabled, pending: 0,
          message: 'Supabase not configured — running local-only.'));
      return;
    }
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((_) => unawaited(syncNow()));
    _ticker = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    unawaited(syncNow());
  }

  void dispose() {
    _connSub?.cancel();
    _ticker?.cancel();
    _statusCtrl.close();
  }

  Future<void> syncNow() async {
    if (!SupabaseConfig.configured) return;

    final pending = await _ledger.unsyncedEntries();
    if (pending.isEmpty) {
      _emit(SyncStatus(
        state: SyncState.idle,
        pending: 0,
        lastSyncAt: _last.lastSyncAt,
      ));
      return;
    }

    final results = await Connectivity().checkConnectivity();
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!online) {
      _emit(SyncStatus(state: SyncState.offline, pending: pending.length));
      return;
    }

    _emit(SyncStatus(state: SyncState.syncing, pending: pending.length));

    try {
      final client = Supabase.instance.client;
      // Push in batches to keep payloads reasonable on poor connections.
      const batchSize = 100;
      for (var i = 0; i < pending.length; i += batchSize) {
        final slice = pending.sublist(
            i, (i + batchSize).clamp(0, pending.length));
        final payload = slice.map((e) => e.toRemoteMap()).toList();
        await client.from('journal_entries').upsert(payload);
        await _ledger.markSynced(slice.map((e) => e.id));
      }
      _emit(SyncStatus(
        state: SyncState.idle,
        pending: 0,
        lastSyncAt: DateTime.now(),
      ));
    } catch (e) {
      _emit(SyncStatus(
          state: SyncState.error,
          pending: pending.length,
          message: e.toString()));
    }
  }

  void _emit(SyncStatus s) {
    _last = s;
    _statusCtrl.add(s);
  }
}
