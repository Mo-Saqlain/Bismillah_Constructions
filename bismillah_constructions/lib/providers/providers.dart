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

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final repo = await ref.watch(entityRepoProvider.future);
  return BackupService(repo);
});

/// Trigger a silent backup once on app boot when older than 6 hours.
final backupBootCheckProvider = FutureProvider<void>((ref) async {
  final svc = await ref.watch(backupServiceProvider.future);
  await svc.maybeRunSilentBackup();
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

final customersProvider = FutureProvider<List<Party>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.customers();
});

final suppliersProvider = FutureProvider<List<Party>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.suppliers();
});

final banksProvider = FutureProvider<List<Bank>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.banks();
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
  final double cash;
  final double bankHbl;
  final double bankMeezan;
  final double bankAlfalah;
  final double supervisorFloat;
  final double receivables;
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
    required this.bankHbl,
    required this.bankMeezan,
    required this.bankAlfalah,
    required this.supervisorFloat,
    required this.receivables,
    required this.payables,
    required this.materialCosts,
    required this.labourCosts,
    required this.revenue,
    required this.serviceFeeIncome,
    required this.personalDraw,
    required this.counterReceivables,
    required this.counterPayables,
  });

  /// Bank ledgers + supervisor float (spec section 6).
  double get liquidCash =>
      bankHbl + bankMeezan + bankAlfalah + cash + supervisorFloat;

  double get totalCashAndBank => liquidCash;

  /// Spec section 6: Liquid_Cash - Total_Supplier_Payables.
  double get netLiquidity => liquidCash - payables;

  double get assets => liquidCash + receivables + counterReceivables;
  double get liabilities => payables + counterPayables;
  double get netProfit =>
      revenue + serviceFeeIncome - (materialCosts + labourCosts + personalDraw);
  double get equity => assets - liabilities;

  double get netPosition =>
      (receivables + counterReceivables) - (payables + counterPayables);

  double get totalNetWorth => liquidCash + netPosition;
}

final accountSummaryProvider = FutureProvider<AccountSummary>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  final entityRepo = await ref.watch(entityRepoProvider.future);

  Future<double> dr(String id) => repo.accountBalance(id);
  Future<double> cr(String id) => repo.creditBalance(id);

  final results = await Future.wait([
    dr(Accounts.cash.id),
    dr(Accounts.bankHbl.id),
    dr(Accounts.bankMeezan.id),
    dr(Accounts.bankAlfalah.id),
    dr(Accounts.supervisorFloat.id),
    dr(Accounts.clientReceivables.id),
    cr(Accounts.supplierPayables.id),
    dr(Accounts.materialCosts.id),
    dr(Accounts.labourCosts.id),
    cr(Accounts.projectRevenue.id),
    cr(Accounts.serviceFeeIncome.id),
    dr(Accounts.personalDraw.id),
  ]);

  final entities = await entityRepo.counterEntities();
  final counterRecv = entities
      .where((e) => e.type == CounterEntityType.receivable)
      .fold<double>(0, (s, e) => s + e.amount);
  final counterPay = entities
      .where((e) => e.type == CounterEntityType.payable)
      .fold<double>(0, (s, e) => s + e.amount);

  return AccountSummary(
    cash: results[0],
    bankHbl: results[1],
    bankMeezan: results[2],
    bankAlfalah: results[3],
    supervisorFloat: results[4],
    receivables: results[5],
    payables: results[6],
    materialCosts: results[7],
    labourCosts: results[8],
    revenue: results[9],
    serviceFeeIncome: results[10],
    personalDraw: results[11],
    counterReceivables: counterRecv,
    counterPayables: counterPay,
  );
});
