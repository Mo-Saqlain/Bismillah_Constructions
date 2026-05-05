import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../data/db/local_db.dart';
import '../data/models/bank.dart';
import '../data/models/change_log.dart';
import '../data/models/counter_entity.dart';
import '../data/models/journal_entry.dart';
import '../data/models/party.dart';
import '../data/models/project.dart';
import '../data/repositories/entity_repository.dart';
import '../data/repositories/ledger_repository.dart';
import '../data/services/backup_service.dart';
import '../data/services/mongo_backup_service.dart';
import '../data/sync/sync_service.dart';

final ledgerVersionProvider = StateProvider<int>((_) => 0);

void bumpLedger(WidgetRef ref) {
  ref.read(ledgerVersionProvider.notifier).update((v) => v + 1);
}

final dbProvider = FutureProvider<Database>((ref) async {
  return LocalDb.instance.open();
});

final ledgerRepoProvider = FutureProvider<LedgerRepository>((ref) async {
  final db = await ref.watch(dbProvider.future);
  return LedgerRepository(db);
});

final entityRepoProvider = FutureProvider<EntityRepository>((ref) async {
  final db = await ref.watch(dbProvider.future);
  return EntityRepository(db);
});

final syncServiceFutureProvider = FutureProvider<SyncService>((ref) async {
  final ledger = await ref.watch(ledgerRepoProvider.future);
  final svc = SyncService(ledger);
  ref.onDispose(svc.dispose);
  svc.start();
  return svc;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final svc = await ref.watch(syncServiceFutureProvider.future);
  yield SyncStatus.initial;
  yield* svc.status;
});

final mongoBackupServiceProvider =
    FutureProvider<MongoBackupService>((ref) async {
  final repo = await ref.watch(entityRepoProvider.future);
  final svc = MongoBackupService(repo);
  ref.onDispose(svc.dispose);
  svc.start();
  return svc;
});

final cloudBackupStatusProvider =
    StreamProvider<CloudBackupStatus>((ref) async* {
  final svc = await ref.watch(mongoBackupServiceProvider.future);
  yield CloudBackupStatus.initial;
  yield* svc.status;
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final repo = await ref.watch(entityRepoProvider.future);
  final cloud = await ref.watch(mongoBackupServiceProvider.future);
  return BackupService(repo, cloud: cloud);
});

/// Trigger a silent backup once on app boot when older than 6 hours.
final backupBootCheckProvider = FutureProvider<void>((ref) async {
  final svc = await ref.watch(backupServiceProvider.future);
  await svc.maybeRunSilentBackup();
});

/// Wires every successful ledger commit to a debounced cloud upload + a
/// Supabase row push. Watched once at app boot so the listeners stay alive
/// for the lifetime of the app.
final commitSyncWiringProvider = FutureProvider<void>((ref) async {
  final ledger = await ref.watch(ledgerRepoProvider.future);
  final cloud = await ref.watch(mongoBackupServiceProvider.future);
  final sync = await ref.watch(syncServiceFutureProvider.future);

  void onCommit() {
    cloud.scheduleUpload();
    unawaited(sync.syncNow());
  }

  ledger.addCommitListener(onCommit);
  ref.onDispose(() => ledger.removeCommitListener(onCommit));
});

// ---- Theme ----

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final repo = await ref.read(entityRepoProvider.future);
    final v = await repo.getSetting(SettingsKeys.themeMode);
    state = switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final repo = await ref.read(entityRepoProvider.future);
    await repo.setSetting(SettingsKeys.themeMode, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ---- Entity lists ----

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.projects();
});

final activeProjectsProvider = FutureProvider<List<Project>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.projects(activeOnly: true);
});

final archivedProjectsProvider = FutureProvider<List<Project>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.archivedProjects();
});

final suppliersProvider = FutureProvider<List<Party>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.suppliers();
});

final archivedSuppliersProvider = FutureProvider<List<Party>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.archivedSuppliers();
});

final banksProvider = FutureProvider<List<Bank>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.banks();
});

final archivedBanksProvider = FutureProvider<List<Bank>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.archivedBanks();
});

/// Cash-like accounts for the transaction form / dashboard.
/// Combines the system Cash + Supervisor Float with every user-defined bank.
final cashLikeAccountsProvider =
    FutureProvider<List<Account>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final banks = await ref.watch(banksProvider.future);
  return [
    ...Accounts.systemCashLike,
    ...banks.map(
      (b) => Account(b.id, b.name, AccountType.asset),
    ),
  ];
});

final counterEntitiesProvider =
    FutureProvider<List<CounterEntity>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.counterEntities();
});

// ---- Ledger reads ----

final recentEntriesProvider = FutureProvider<List<JournalEntry>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.recentEntries(limit: 100);
});

final allEntriesProvider = FutureProvider<List<JournalEntry>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.allEntries();
});

final allEntriesIncludingDeletedProvider =
    FutureProvider<List<JournalEntry>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.allEntries(includeDeleted: true);
});

final changeLogProvider = FutureProvider<List<ChangeLog>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.changeLog();
});

// ---- Account summary ----

class AccountSummary {
  /// System cash (Cash account).
  final double cash;

  /// Supervisor Float account.
  final double supervisorFloat;

  /// Per user-defined bank balance, keyed by bank id. The bank's display name
  /// is on the corresponding [Bank] row.
  final Map<String, double> bankBalances;

  /// Outstanding supplier payables (credits − debits).
  final double payables;

  final double materialCosts;
  final double labourCosts;
  final double revenue;
  final double serviceFeeIncome;
  final double personalDraw;

  final double counterReceivables;
  final double counterPayables;

  const AccountSummary({
    required this.cash,
    required this.supervisorFloat,
    required this.bankBalances,
    required this.payables,
    required this.materialCosts,
    required this.labourCosts,
    required this.revenue,
    required this.serviceFeeIncome,
    required this.personalDraw,
    required this.counterReceivables,
    required this.counterPayables,
  });

  double get totalBanks =>
      bankBalances.values.fold<double>(0, (a, b) => a + b);

  /// Cash + Supervisor Float + every user-defined bank.
  double get liquidCash => cash + supervisorFloat + totalBanks;

  /// Spec section 6: Liquid_Cash − Total_Supplier_Payables.
  double get netLiquidity => liquidCash - payables;

  double get assets => liquidCash + counterReceivables;
  double get liabilities => payables + counterPayables;
  double get netProfit =>
      revenue + serviceFeeIncome - (materialCosts + labourCosts + personalDraw);
  double get equity => assets - liabilities;

  double get netPosition => counterReceivables - (payables + counterPayables);
  double get totalNetWorth => liquidCash + netPosition;
}

final accountSummaryProvider = FutureProvider<AccountSummary>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  final entityRepo = await ref.watch(entityRepoProvider.future);
  final banks = await ref.watch(banksProvider.future);

  Future<double> dr(String id) => repo.accountBalance(id);
  Future<double> cr(String id) => repo.creditBalance(id);

  final fixed = await Future.wait([
    dr(Accounts.cash.id),
    dr(Accounts.supervisorFloat.id),
    cr(Accounts.supplierPayables.id),
    dr(Accounts.materialCosts.id),
    dr(Accounts.labourCosts.id),
    cr(Accounts.projectRevenue.id),
    cr(Accounts.serviceFeeIncome.id),
    dr(Accounts.personalDraw.id),
  ]);

  final bankBalances = <String, double>{
    for (final b in banks) b.id: await dr(b.id),
  };

  final entities = await entityRepo.counterEntities();
  final counterRecv = entities
      .where((e) => e.type == CounterEntityType.receivable)
      .fold<double>(0, (s, e) => s + e.amount);
  final counterPay = entities
      .where((e) => e.type == CounterEntityType.payable)
      .fold<double>(0, (s, e) => s + e.amount);

  return AccountSummary(
    cash: fixed[0],
    supervisorFloat: fixed[1],
    bankBalances: bankBalances,
    payables: fixed[2],
    materialCosts: fixed[3],
    labourCosts: fixed[4],
    revenue: fixed[5],
    serviceFeeIncome: fixed[6],
    personalDraw: fixed[7],
    counterReceivables: counterRecv,
    counterPayables: counterPay,
  );
});
