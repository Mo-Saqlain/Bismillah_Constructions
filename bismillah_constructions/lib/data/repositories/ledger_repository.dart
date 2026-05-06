import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../models/change_log.dart';
import '../models/journal_entry.dart';

const _uuid = Uuid();

/// Single mediator for *all* writes to `journal_entries`.
///
/// Posts are double-entry (one debit row + one credit row sharing a
/// `transaction_id`). Soft-deletes set `is_deleted = 1`; corrections via
/// reversal post a *new* offsetting transaction.
class LedgerRepository {
  LedgerRepository(this._db);
  final Database _db;

  /// Hooks: callers can attach listeners to know when a write happened so
  /// they can fire a cloud sync. Kept on the repo (not the DB) so background
  /// cron writes don't trigger spurious uploads.
  final List<void Function()> _commitListeners = [];

  void addCommitListener(void Function() listener) =>
      _commitListeners.add(listener);
  void removeCommitListener(void Function() listener) =>
      _commitListeners.remove(listener);
  void _fireCommit() {
    for (final fn in List.of(_commitListeners)) {
      try {
        fn();
      } catch (_) {/* listener errors must not affect the write path */}
    }
  }

  /// Stable per-install identifier, recorded on every audit row for traceability
  /// in a flat-permissions setup. Cached after first read.
  String? _cachedDeviceId;
  Future<String?> _deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId;
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: ['device_id'], limit: 1);
    final v = rows.isEmpty ? null : rows.first['value'] as String?;
    _cachedDeviceId = v;
    return v;
  }

  // -------------------- Posting helpers --------------------

  Future<String> _post({
    required Account debitAccount,
    required Account creditAccount,
    required double amount,
    String? projectId,
    String? supplierId,
    String? customerId,
    String? description,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Amount must be positive (got $amount).');
    }
    final txnId = _uuid.v4();
    final now = DateTime.now().toUtc();

    await _db.transaction((txn) async {
      await txn.insert(
        'journal_entries',
        JournalEntry(
          id: _uuid.v4(),
          transactionId: txnId,
          accountId: debitAccount.id,
          projectId: projectId,
          supplierId: supplierId,
          customerId: customerId,
          debit: amount,
          credit: 0,
          description: description,
          createdAt: now,
        ).toMap(),
      );
      await txn.insert(
        'journal_entries',
        JournalEntry(
          id: _uuid.v4(),
          transactionId: txnId,
          accountId: creditAccount.id,
          projectId: projectId,
          supplierId: supplierId,
          customerId: customerId,
          debit: 0,
          credit: amount,
          description: description,
          createdAt: now,
        ).toMap(),
      );
    });

    _fireCommit();
    return txnId;
  }

  // -------------------- Canonical transactions --------------------

  Future<String> postMaterialBuy({
    required double amount,
    required String projectId,
    required String supplierId,
    String? description,
  }) =>
      _post(
        debitAccount: Accounts.materialCosts,
        creditAccount: Accounts.supplierPayables,
        amount: amount,
        projectId: projectId,
        supplierId: supplierId,
        description: description,
      );

  Future<String> postLabourPayment({
    required double amount,
    required String projectId,
    required String supplierId,
    required Account paidFrom,
    String? description,
  }) async {
    await _assertCashLike(paidFrom);
    return _post(
      debitAccount: Accounts.labourCosts,
      creditAccount: paidFrom,
      amount: amount,
      projectId: projectId,
      supplierId: supplierId,
      description: description,
    );
  }

  Future<String> postSupplierPay({
    required double amount,
    required String supplierId,
    required Account paidFrom,
    String? projectId,
    String? description,
  }) async {
    await _assertCashLike(paidFrom);
    return _post(
      debitAccount: Accounts.supplierPayables,
      creditAccount: paidFrom,
      amount: amount,
      supplierId: supplierId,
      projectId: projectId,
      description: description,
    );
  }

  /// Direct receipt from project — no receivable phase. Money moves from the
  /// client into a cash/bank account and is booked as project revenue at the
  /// same time. The project_id is mandatory because the user removed the
  /// separate Customer entity and the project is the only counterparty.
  Future<String> postReceiveFromProject({
    required double amount,
    required String projectId,
    required Account receivedInto,
    String? description,
  }) async {
    await _assertCashLike(receivedInto);
    return _post(
      debitAccount: receivedInto,
      creditAccount: Accounts.projectRevenue,
      amount: amount,
      projectId: projectId,
      description: description,
    );
  }

  /// Inter-wallet transfer. Does NOT touch payables (spec section 1).
  Future<String> postWalletTransfer({
    required double amount,
    required Account from,
    required Account to,
    String? description,
  }) async {
    await _assertCashLike(from);
    await _assertCashLike(to);
    if (from.id == to.id) {
      throw ArgumentError('Source and destination wallet must differ.');
    }
    return _post(
      debitAccount: to,
      creditAccount: from,
      amount: amount,
      description: description ?? 'Transfer ${from.name} → ${to.name}',
    );
  }

  /// Personal / daily expense draw. Reduces liquid cash but leaves supplier
  /// payables intact (spec section 1).
  Future<String> postPersonalDraw({
    required double amount,
    required Account paidFrom,
    String? description,
  }) async {
    await _assertCashLike(paidFrom);
    return _post(
      debitAccount: Accounts.personalDraw,
      creditAccount: paidFrom,
      amount: amount,
      description: description,
    );
  }

  /// Opening balance for a freshly-created bank/wallet. Posts
  /// Dr Bank / Cr Owner's Equity so the asset is properly recognized in the
  /// double-entry books.
  Future<String?> postOpeningBalance({
    required Account bankAccount,
    required double amount,
  }) async {
    if (amount <= 0) return null;
    return _post(
      debitAccount: bankAccount,
      creditAccount: Accounts.ownersEquity,
      amount: amount,
      description: 'Opening balance',
    );
  }

  /// Service fee for Labour-Rate model (spec section 2 / interim fees).
  Future<String> postServiceFee({
    required double amount,
    required String projectId,
    required Account receivedInto,
    String? description,
  }) async {
    await _assertCashLike(receivedInto);
    return _post(
      debitAccount: receivedInto,
      creditAccount: Accounts.serviceFeeIncome,
      amount: amount,
      projectId: projectId,
      description: description,
    );
  }

  /// Returns true if [accountId] is a system cash-like account (Cash /
  /// Supervisor Float) OR a user-defined bank/wallet (row in `banks`).
  Future<bool> _isCashLikeId(String accountId) async {
    if (Accounts.systemCashLike.any((a) => a.id == accountId)) return true;
    final rows = await _db.rawQuery(
      'SELECT 1 FROM banks WHERE id = ? LIMIT 1', [accountId]);
    return rows.isNotEmpty;
  }

  Future<void> _assertCashLike(Account a) async {
    if (!await _isCashLikeId(a.id)) {
      throw ArgumentError('Account ${a.id} is not a cash/bank account.');
    }
  }

  /// Snapshot of cash-like account ids at a point in time. Used by
  /// aggregations like [monthlyCashFlow] that need to filter by a fixed set.
  Future<List<String>> cashLikeAccountIds() async {
    final banks = await _db.query('banks');
    return [
      ...Accounts.systemCashLike.map((a) => a.id),
      ...banks.map((r) => r['id'] as String),
    ];
  }

  // -------------------- Reversal & soft delete --------------------

  Future<String> postReversal(String originalTxnId, {String? note}) async {
    final rows = await _db.query('journal_entries',
        where: 'transaction_id = ?', whereArgs: [originalTxnId]);
    if (rows.length != 2) {
      throw StateError(
          'Expected 2 rows for txn $originalTxnId, found ${rows.length}');
    }
    final pair = rows.map(JournalEntry.fromMap).toList();
    final debitRow = pair.firstWhere((r) => r.debit > 0);
    final creditRow = pair.firstWhere((r) => r.credit > 0);
    final amount = debitRow.debit;
    final desc = note ?? 'Reversal of txn $originalTxnId';

    final newTxnId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.transaction((txn) async {
      await txn.insert(
          'journal_entries',
          JournalEntry(
            id: _uuid.v4(),
            transactionId: newTxnId,
            accountId: debitRow.accountId,
            projectId: debitRow.projectId,
            supplierId: debitRow.supplierId,
            customerId: debitRow.customerId,
            debit: 0,
            credit: amount,
            description: desc,
            createdAt: now,
          ).toMap());
      await txn.insert(
          'journal_entries',
          JournalEntry(
            id: _uuid.v4(),
            transactionId: newTxnId,
            accountId: creditRow.accountId,
            projectId: creditRow.projectId,
            supplierId: creditRow.supplierId,
            customerId: creditRow.customerId,
            debit: amount,
            credit: 0,
            description: desc,
            createdAt: now,
          ).toMap());
    });
    _fireCommit();
    return newTxnId;
  }

  /// Soft-delete a transaction (both rows). Removed from active balance,
  /// kept visible in archive view. Logged in `change_log`.
  Future<void> softDeleteTransaction(String transactionId,
      {String? note}) async {
    final rows = await _db.query('journal_entries',
        where: 'transaction_id = ? AND is_deleted = 0',
        whereArgs: [transactionId]);
    if (rows.isEmpty) return;
    final original = rows.map(JournalEntry.fromMap).toList();
    final now = DateTime.now().toUtc();
    final dev = await _deviceId();

    await _db.transaction((txn) async {
      await txn.update(
        'journal_entries',
        {'is_deleted': 1, 'deleted_at': now.toIso8601String()},
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );
      await txn.insert(
          'change_log',
          ChangeLog(
            id: _uuid.v4(),
            entityType: 'journal_entry',
            entityId: transactionId,
            action: ChangeAction.delete,
            originalData: jsonEncode(original.map((e) => e.toMap()).toList()),
            note: note,
            deviceId: dev,
            timestamp: now,
          ).toMap());
    });
    _fireCommit();
  }

  /// Permanently remove both rows of a transaction. The original payload is
  /// preserved in `change_log` for audit. Use this when the user wants the
  /// transaction *gone* from history (soft delete keeps it visible in
  /// "Show deleted" mode).
  Future<void> hardDeleteTransaction(String transactionId,
      {String? note}) async {
    final rows = await _db.query('journal_entries',
        where: 'transaction_id = ?', whereArgs: [transactionId]);
    if (rows.isEmpty) return;
    final original = rows.map(JournalEntry.fromMap).toList();
    final now = DateTime.now().toUtc();
    final dev = await _deviceId();

    await _db.transaction((txn) async {
      await txn.delete('journal_entries',
          where: 'transaction_id = ?', whereArgs: [transactionId]);
      await txn.insert(
          'change_log',
          ChangeLog(
            id: _uuid.v4(),
            entityType: 'journal_entry',
            entityId: transactionId,
            action: ChangeAction.delete,
            originalData: jsonEncode(original.map((e) => e.toMap()).toList()),
            note: note ?? 'hard delete',
            deviceId: dev,
            timestamp: now,
          ).toMap());
    });
    _fireCommit();
  }

  /// Restore a soft-deleted transaction.
  Future<void> restoreTransaction(String transactionId,
      {String? note}) async {
    final rows = await _db.query('journal_entries',
        where: 'transaction_id = ? AND is_deleted = 1',
        whereArgs: [transactionId]);
    if (rows.isEmpty) return;
    final now = DateTime.now().toUtc();
    final dev = await _deviceId();

    await _db.transaction((txn) async {
      await txn.update(
        'journal_entries',
        {'is_deleted': 0, 'deleted_at': null},
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );
      await txn.insert(
          'change_log',
          ChangeLog(
            id: _uuid.v4(),
            entityType: 'journal_entry',
            entityId: transactionId,
            action: ChangeAction.restore,
            note: note,
            deviceId: dev,
            timestamp: now,
          ).toMap());
    });
    _fireCommit();
  }

  // -------------------- Reads --------------------

  /// Live entries — excludes soft-deleted by default.
  Future<List<JournalEntry>> recentEntries({int limit = 50}) async {
    final rows = await _db.query('journal_entries',
        where: 'is_deleted = 0',
        orderBy: 'created_at DESC',
        limit: limit);
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> allEntries({bool includeDeleted = false}) async {
    final rows = await _db.query('journal_entries',
        where: includeDeleted ? null : 'is_deleted = 0',
        orderBy: 'created_at DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> deletedEntries() async {
    final rows = await _db.query('journal_entries',
        where: 'is_deleted = 1', orderBy: 'deleted_at DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> entriesForSupplier(String supplierId,
      {String? projectId, bool includeDeleted = false}) async {
    final where = StringBuffer('supplier_id = ?');
    final args = <Object>[supplierId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> entriesForCustomer(String customerId,
      {bool includeDeleted = false}) async {
    final where = StringBuffer('customer_id = ?');
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: [customerId],
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Every journal row that touches a specific account (typically a bank /
  /// wallet id), oldest → newest. Used by the bank ledger report to build a
  /// running balance.
  Future<List<JournalEntry>> entriesForAccount(String accountId,
      {bool includeDeleted = false}) async {
    final where = StringBuffer('account_id = ?');
    final args = <Object>[accountId];
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> entriesForProject(String projectId,
      {bool includeDeleted = false}) async {
    final where = StringBuffer('project_id = ?');
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: [projectId],
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Sum(debit) - sum(credit). Always excludes soft-deleted rows.
  Future<double> accountBalance(String accountId, {String? projectId}) async {
    final where = StringBuffer('account_id = ? AND is_deleted = 0');
    final args = <Object>[accountId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0) AS bal '
      'FROM journal_entries WHERE ${where.toString()}',
      args,
    );
    return ((rows.first['bal'] as num?) ?? 0).toDouble();
  }

  Future<double> creditBalance(String accountId, {String? projectId}) async {
    final bal = await accountBalance(accountId, projectId: projectId);
    return -bal;
  }

  /// Sum of debits to a specific account, optionally filtered by project.
  Future<double> sumDebits(String accountId, {String? projectId}) async {
    final where = StringBuffer('account_id = ? AND is_deleted = 0');
    final args = <Object>[accountId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) AS s FROM journal_entries WHERE ${where.toString()}',
      args,
    );
    return ((rows.first['s'] as num?) ?? 0).toDouble();
  }

  Future<double> sumCredits(String accountId, {String? projectId}) async {
    final where = StringBuffer('account_id = ? AND is_deleted = 0');
    final args = <Object>[accountId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(credit),0) AS s FROM journal_entries WHERE ${where.toString()}',
      args,
    );
    return ((rows.first['s'] as num?) ?? 0).toDouble();
  }

  /// Project reconciliation snapshot.
  ///
  /// New rule (post-customer-removal): a With-Material project is "reconciled"
  /// when supplier payables for that project are zero. Money received from the
  /// project is booked directly as revenue, so the cash-vs-cost balance is
  /// `revenue - costs = savings` (positive = profit).
  Future<ProjectReconciliation> reconcileProject(String projectId) async {
    final projectInflow =
        await sumCredits(Accounts.projectRevenue.id, projectId: projectId);

    final supplierPaid =
        await sumDebits(Accounts.supplierPayables.id, projectId: projectId);

    final credits = await sumCredits(Accounts.supplierPayables.id,
        projectId: projectId);
    final supplierPayables = credits - supplierPaid;

    return ProjectReconciliation(
      projectInflow: projectInflow,
      supplierPaid: supplierPaid,
      supplierPayables: supplierPayables,
    );
  }

  /// Total project outflow = material costs + labour costs for project.
  Future<double> projectOutflow(String projectId) async {
    final mat =
        await sumDebits(Accounts.materialCosts.id, projectId: projectId);
    final lab = await sumDebits(Accounts.labourCosts.id, projectId: projectId);
    return mat + lab;
  }

  // -------------------- Aging Analysis --------------------

  /// Aging buckets across 0-30 / 31-60 / 61-90 / 90+ days for an account that
  /// represents an outstanding balance (Client Receivables, Supplier Payables).
  ///
  /// We bucket the *outstanding* portion per party using FIFO matching against
  /// payments: the oldest open invoice's age determines the bucket. This keeps
  /// the calculation accurate without invoice-level invoicing tables.
  Future<AgingReport> aging({
    required String partyAccountId,
    required bool isReceivable,
    DateTime? asOf,
  }) async {
    final now = (asOf ?? DateTime.now()).toUtc();
    final rows = await _db.query(
      'journal_entries',
      where: 'account_id = ? AND is_deleted = 0',
      whereArgs: [partyAccountId],
      orderBy: 'created_at ASC',
    );
    // For receivables: debits = invoice raised, credits = payment received.
    // For payables:    credits = bill incurred, debits = payment made.
    final byParty = <String, List<JournalEntry>>{};
    for (final row in rows) {
      final je = JournalEntry.fromMap(row);
      final partyId = isReceivable ? je.customerId : je.supplierId;
      if (partyId == null) continue;
      byParty.putIfAbsent(partyId, () => []).add(je);
    }

    final lines = <AgingLine>[];
    byParty.forEach((partyId, entries) {
      // FIFO open-balance queue: each invoice contributes to the queue, each
      // payment consumes from the head.
      final open = <_OpenInvoice>[];
      for (final e in entries) {
        final amt = isReceivable
            ? (e.debit - e.credit)
            : (e.credit - e.debit);
        if (amt > 0) {
          open.add(_OpenInvoice(date: e.createdAt, remaining: amt));
        } else if (amt < 0) {
          var pay = -amt;
          while (pay > 0 && open.isNotEmpty) {
            final head = open.first;
            if (head.remaining <= pay) {
              pay -= head.remaining;
              open.removeAt(0);
            } else {
              head.remaining -= pay;
              pay = 0;
            }
          }
        }
      }
      var b0 = 0.0, b30 = 0.0, b60 = 0.0, b90 = 0.0;
      for (final inv in open) {
        final days = now.difference(inv.date).inDays;
        if (days <= 30) {
          b0 += inv.remaining;
        } else if (days <= 60) {
          b30 += inv.remaining;
        } else if (days <= 90) {
          b60 += inv.remaining;
        } else {
          b90 += inv.remaining;
        }
      }
      final total = b0 + b30 + b60 + b90;
      if (total > 0.005) {
        lines.add(AgingLine(
          partyId: partyId,
          bucket0_30: b0,
          bucket31_60: b30,
          bucket61_90: b60,
          bucket90Plus: b90,
        ));
      }
    });
    lines.sort((a, b) => b.total.compareTo(a.total));
    return AgingReport(asOf: now, lines: lines);
  }

  // -------------------- Cash Flow --------------------

  /// Monthly delta-cash per cash-like account, oldest -> newest, capped at
  /// `monthsBack`. Each row is [month, perAccountDelta]. The account id list
  /// is built dynamically from system cash + the user-defined `banks` table.
  Future<List<MonthlyCashFlow>> monthlyCashFlow({int monthsBack = 12}) async {
    final now = DateTime.now().toUtc();
    final start =
        DateTime.utc(now.year, now.month - (monthsBack - 1), 1);
    final ids = await cashLikeAccountIds();
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT account_id, debit, credit, created_at '
      'FROM journal_entries '
      'WHERE is_deleted = 0 '
      "AND account_id IN ($placeholders) "
      'AND created_at >= ?',
      [...ids, start.toIso8601String()],
    );

    final byMonth = <String, Map<String, double>>{};
    for (final r in rows) {
      final ts = DateTime.parse(r['created_at'] as String).toUtc();
      final key =
          '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
      final acc = r['account_id'] as String;
      final delta =
          ((r['debit'] as num).toDouble()) - ((r['credit'] as num).toDouble());
      byMonth
          .putIfAbsent(key, () => {})
          .update(acc, (v) => v + delta, ifAbsent: () => delta);
    }
    final out = <MonthlyCashFlow>[];
    for (var i = 0; i < monthsBack; i++) {
      final m = DateTime.utc(start.year, start.month + i, 1);
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      out.add(MonthlyCashFlow(month: m, perAccount: byMonth[key] ?? const {}));
    }
    return out;
  }

  // -------------------- Wage Register --------------------

  /// Returns LABOUR_COSTS debits grouped by supplier (worker), with totals
  /// over the optional `[from, to]` window.
  Future<List<WageRegisterLine>> wageRegister(
      {DateTime? from, DateTime? to}) async {
    final where = StringBuffer(
        'account_id = ? AND is_deleted = 0 AND debit > 0 AND supplier_id IS NOT NULL');
    final args = <Object>[Accounts.labourCosts.id];
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.toUtc().toIso8601String());
    }
    final rows = await _db.rawQuery(
      'SELECT supplier_id, COUNT(*) AS payments, SUM(debit) AS total, '
      'MAX(created_at) AS last_paid '
      'FROM journal_entries WHERE ${where.toString()} '
      'GROUP BY supplier_id ORDER BY total DESC',
      args,
    );
    return rows
        .map((r) => WageRegisterLine(
              supplierId: r['supplier_id'] as String,
              paymentCount: (r['payments'] as num).toInt(),
              totalPaid: (r['total'] as num).toDouble(),
              lastPaidAt: DateTime.parse(r['last_paid'] as String),
            ))
        .toList();
  }

  // -------------------- Budget vs Actual --------------------

  /// Per-category actual spend on a project, suitable for comparing against
  /// `Project.budget`. Returns material costs split by [MaterialType] plus a
  /// labour bucket and an "other" bucket for personal draws against project.
  Future<ProjectBva> projectBva(String projectId) async {
    final material =
        await sumDebits(Accounts.materialCosts.id, projectId: projectId);
    final labour =
        await sumDebits(Accounts.labourCosts.id, projectId: projectId);

    // Split material by type via material_inventory totals.
    final matRows = await _db.rawQuery(
      'SELECT material_type, SUM(total_cost) AS s '
      'FROM material_inventory WHERE project_id = ? AND txn_type = ? '
      'GROUP BY material_type',
      [projectId, MaterialTxnType.purchase.db],
    );
    final byMaterial = <MaterialType, double>{};
    for (final r in matRows) {
      final t = MaterialTypeX.fromDb(r['material_type'] as String);
      byMaterial[t] = (r['s'] as num).toDouble();
    }
    // Reconcile rounding: any material posted via journals that isn't in
    // material_inventory ends up under "other material".
    final invSum = byMaterial.values.fold<double>(0, (a, b) => a + b);
    final otherMaterial = (material - invSum).clamp(0, double.infinity);

    return ProjectBva(
      materialByType: byMaterial,
      otherMaterial: otherMaterial.toDouble(),
      labour: labour,
    );
  }

  // -------------------- Price Trend --------------------

  /// Time-series of unit rates per [MaterialType] from `material_inventory`,
  /// for the last `monthsBack` months. Each entry is `(date, rate)`.
  Future<Map<MaterialType, List<PricePoint>>> priceTrend(
      {int monthsBack = 12}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: 30 * monthsBack));
    final rows = await _db.rawQuery(
      'SELECT material_type, rate, created_at '
      'FROM material_inventory WHERE txn_type = ? AND created_at >= ? '
      'ORDER BY created_at ASC',
      [MaterialTxnType.purchase.db, cutoff.toIso8601String()],
    );
    final out = <MaterialType, List<PricePoint>>{};
    for (final r in rows) {
      final t = MaterialTypeX.fromDb(r['material_type'] as String);
      out
          .putIfAbsent(t, () => [])
          .add(PricePoint(
            date: DateTime.parse(r['created_at'] as String),
            rate: (r['rate'] as num).toDouble(),
          ));
    }
    return out;
  }

  // -------------------- Burn Chart --------------------

  /// Cumulative project outflow series — one point per spend transaction.
  Future<List<BurnPoint>> projectBurn(String projectId) async {
    final rows = await _db.rawQuery(
      'SELECT debit, created_at FROM journal_entries '
      'WHERE is_deleted = 0 AND project_id = ? '
      'AND account_id IN (?, ?) AND debit > 0 '
      'ORDER BY created_at ASC',
      [projectId, Accounts.materialCosts.id, Accounts.labourCosts.id],
    );
    final out = <BurnPoint>[];
    var running = 0.0;
    for (final r in rows) {
      running += (r['debit'] as num).toDouble();
      out.add(BurnPoint(
        date: DateTime.parse(r['created_at'] as String),
        cumulativeSpend: running,
      ));
    }
    return out;
  }

  // -------------------- Sync helpers --------------------

  Future<List<JournalEntry>> unsyncedEntries() async {
    final rows = await _db.query('journal_entries',
        where: 'synced = 0', orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<void> markSynced(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.rawUpdate(
      'UPDATE journal_entries SET synced = 1 WHERE id IN ($placeholders)',
      ids.toList(),
    );
  }
}

class MonthlyCashFlow {
  final DateTime month;
  final Map<String, double> perAccount;
  const MonthlyCashFlow({required this.month, required this.perAccount});
  double get total => perAccount.values.fold(0, (a, b) => a + b);
}

class WageRegisterLine {
  final String supplierId;
  final int paymentCount;
  final double totalPaid;
  final DateTime lastPaidAt;
  const WageRegisterLine({
    required this.supplierId,
    required this.paymentCount,
    required this.totalPaid,
    required this.lastPaidAt,
  });
}

class ProjectBva {
  final Map<MaterialType, double> materialByType;
  final double otherMaterial;
  final double labour;
  const ProjectBva({
    required this.materialByType,
    required this.otherMaterial,
    required this.labour,
  });
  double get totalMaterial =>
      materialByType.values.fold<double>(0, (a, b) => a + b) + otherMaterial;
  double get totalSpend => totalMaterial + labour;
}

class PricePoint {
  final DateTime date;
  final double rate;
  const PricePoint({required this.date, required this.rate});
}

class BurnPoint {
  final DateTime date;
  final double cumulativeSpend;
  const BurnPoint({required this.date, required this.cumulativeSpend});
}

class _OpenInvoice {
  _OpenInvoice({required this.date, required this.remaining});
  final DateTime date;
  double remaining;
}

class AgingLine {
  final String partyId;
  final double bucket0_30;
  final double bucket31_60;
  final double bucket61_90;
  final double bucket90Plus;
  const AgingLine({
    required this.partyId,
    required this.bucket0_30,
    required this.bucket31_60,
    required this.bucket61_90,
    required this.bucket90Plus,
  });
  double get total => bucket0_30 + bucket31_60 + bucket61_90 + bucket90Plus;
}

class AgingReport {
  final DateTime asOf;
  final List<AgingLine> lines;
  const AgingReport({required this.asOf, required this.lines});

  double get total0_30 =>
      lines.fold(0, (s, l) => s + l.bucket0_30);
  double get total31_60 =>
      lines.fold(0, (s, l) => s + l.bucket31_60);
  double get total61_90 =>
      lines.fold(0, (s, l) => s + l.bucket61_90);
  double get total90Plus =>
      lines.fold(0, (s, l) => s + l.bucket90Plus);
  double get grandTotal =>
      total0_30 + total31_60 + total61_90 + total90Plus;
}

class ProjectReconciliation {
  /// Total received from the project (credits to PROJECT_REV for this project).
  final double projectInflow;

  /// Sum of debits to SUPPLIER_PAY for this project.
  final double supplierPaid;

  /// Outstanding payables (credits − debits) on SUPPLIER_PAY for this project.
  final double supplierPayables;

  const ProjectReconciliation({
    required this.projectInflow,
    required this.supplierPaid,
    required this.supplierPayables,
  });

  /// New rule (post-customer-removal): reconciled when no payables remain.
  /// The cash received minus costs incurred is the project's savings/profit
  /// and does not need to balance to zero.
  bool get isBalanced => supplierPayables.abs() < 0.01;

  /// Net cash position from project = inflow − supplier obligations (paid + open).
  double get savings => projectInflow - (supplierPaid + supplierPayables);
}
