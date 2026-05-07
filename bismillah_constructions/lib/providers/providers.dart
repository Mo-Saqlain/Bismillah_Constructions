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
import '../data/models/labour_type_def.dart';
import '../data/models/material_type_def.dart';
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
  final svc = BackupService(repo);
  // Make sure a stable device id exists for the audit log.
  unawaited(svc.ensureDeviceId());
  return svc;
});

/// Trigger a silent backup once on app boot when older than 6 hours.
final backupBootCheckProvider = FutureProvider<void>((ref) async {
  final svc = await ref.watch(backupServiceProvider.future);
  await svc.maybeRunSilentBackup();
});

/// Wires every successful ledger commit to a Supabase row push. Watched
/// once at app boot so the listener stays alive for the lifetime of the app.
final commitSyncWiringProvider = FutureProvider<void>((ref) async {
  final ledger = await ref.watch(ledgerRepoProvider.future);
  final sync = await ref.watch(syncServiceFutureProvider.future);

  void onCommit() {
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

/// User-defined + built-in material categories. Bumping
/// [ledgerVersionProvider] after add/delete refreshes the dropdown
/// everywhere that watches this list.
final materialTypesProvider =
    FutureProvider<List<MaterialTypeDef>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.materialTypes();
});

final labourTypesProvider =
    FutureProvider<List<LabourTypeDef>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(entityRepoProvider.future);
  return repo.labourTypes();
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

final overallDailySpendProvider =
    FutureProvider<List<DailySpend>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.overallDailySpend(daysBack: 7);
});

/// How many days of current liquid cash the business can sustain at the
/// 30-day average daily burn rate. Null means no spending history yet.
class CashRunway {
  final double? days;
  final double avgDailyExpense;
  const CashRunway({required this.days, required this.avgDailyExpense});

  bool get isGreen => days != null && days! >= 30;
  bool get isYellow => days != null && days! >= 15 && days! < 30;
  bool get isRed => days != null && days! < 15;
}

final cashRunwayProvider = FutureProvider<CashRunway>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  final avgDaily = await repo.averageDailyExpense();
  if (avgDaily <= 0) return const CashRunway(days: null, avgDailyExpense: 0);
  final summary = await ref.watch(accountSummaryProvider.future);
  return CashRunway(
    days: summary.liquidCash / avgDaily,
    avgDailyExpense: avgDaily,
  );
});

final supplierSpendingProvider =
    FutureProvider<List<SupplierSpend>>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.supplierSpending();
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

  /// Per user-defined bank balance, keyed by bank id. The bank's display name
  /// is on the corresponding [Bank] row.
  final Map<String, double> bankBalances;

  /// Outstanding supplier payables (credits − debits).
  final double payables;

  /// Sum of money owed to us by customers (under-funded projects).
  /// Computed via the same FIFO logic as the Aging Receivables report.
  final double projectReceivables;

  /// Sum of advances we are sitting on with our suppliers (we paid more
  /// than we have been billed).
  final double supplierOverpayments;

  final double materialCosts;
  final double labourCosts;
  /// PoC-recognized contract revenue (cost-recovery for active jobs, full
  /// contract on close). NOT raw projectRevenue credits — those would
  /// inflate profit by booking customer deposits as earned income.
  final double revenue;
  final double serviceFeeIncome;
  final double personalDraw;

  /// Sum of (costs - budget) across every project where actual costs
  /// exceeded budget. Recognized as an immediate cost (FASB/IFRS).
  final double lossProvision;

  /// Customer money received but not yet earned — a liability we'd have to
  /// refund / deliver work for. Sum of LR + With-Material deposits.
  final double customerDeposits;

  /// Project-level loss warnings sourced from [LedgerRepository.incomeFigures].
  final List<ProjectAtRisk> projectsAtRisk;

  final double counterReceivables;
  final double counterPayables;

  const AccountSummary({
    required this.cash,
    required this.bankBalances,
    required this.payables,
    required this.projectReceivables,
    required this.supplierOverpayments,
    required this.materialCosts,
    required this.labourCosts,
    required this.revenue,
    required this.serviceFeeIncome,
    required this.personalDraw,
    required this.lossProvision,
    required this.customerDeposits,
    required this.projectsAtRisk,
    required this.counterReceivables,
    required this.counterPayables,
  });

  /// Total amount owed to us — what the home screen's "Receivables" tile
  /// shows. Combines unpaid project work and supplier overpayments.
  double get totalReceivables => projectReceivables + supplierOverpayments;

  double get totalBanks =>
      bankBalances.values.fold<double>(0, (a, b) => a + b);

  /// Cash + every user-defined bank/wallet.
  double get liquidCash => cash + totalBanks;

  /// Spec section 6: Liquid_Cash − Total_Supplier_Payables.
  double get netLiquidity => liquidCash - payables;

  double get assets => liquidCash + counterReceivables;
  double get liabilities => payables + counterPayables;
  double get netProfit =>
      revenue +
      serviceFeeIncome -
      (materialCosts + labourCosts + personalDraw + lossProvision);
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
    cr(Accounts.supplierPayables.id),
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

  // Receivables totals via the FIFO aging logic — same source the Aging
  // Receivables screen uses, so the dashboard tile and the report always
  // agree.
  final receivables = await repo.receivablesTotals();

  // PoC-recognized P&L figures — single source of truth shared with the
  // Income Statement. Avoids fake profit from advance customer payments.
  final income = await repo.incomeFigures();

  return AccountSummary(
    cash: fixed[0],
    bankBalances: bankBalances,
    payables: fixed[1],
    projectReceivables: receivables.projectsOwed,
    supplierOverpayments: receivables.suppliersOverpaid,
    materialCosts: income.matCosts,
    labourCosts: income.labCosts,
    revenue: income.wmRevenue,
    serviceFeeIncome: income.serviceFees,
    personalDraw: fixed[2],
    lossProvision: income.lossProvision,
    customerDeposits: income.totalDeposit,
    projectsAtRisk: income.projectsAtRisk,
    counterReceivables: counterRecv,
    counterPayables: counterPay,
  );
});
