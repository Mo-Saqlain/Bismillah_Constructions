import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../models/change_log.dart';
import '../models/journal_entry.dart';
import '../models/material_item.dart' show resolveMaterialLabel;

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

  // -------------------- Validation helpers --------------------

  /// Throws [ArgumentError] if [value] is null or blank. Used to catch
  /// programming mistakes where a required FK field is passed as an empty
  /// string instead of a valid UUID.
  static void _assertNonEmpty(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      throw ArgumentError('$fieldName must not be null or empty.');
    }
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
  }) {
    _assertNonEmpty(projectId, 'projectId');
    _assertNonEmpty(supplierId, 'supplierId');
    return _post(
      debitAccount: Accounts.materialCosts,
      creditAccount: Accounts.supplierPayables,
      amount: amount,
      projectId: projectId,
      supplierId: supplierId,
      description: description,
    );
  }

  /// Pay a labour worker. If the worker already has wages on credit
  /// (recorded earlier via [postLabourCredit]), this payment **settles the
  /// outstanding payable first** rather than booking a brand-new cost. Only
  /// any excess beyond what is owed becomes a new direct labour cost.
  ///
  /// Without this rule, paying a worker after recording their wages on
  /// credit would double-count: Labour Costs would jump to 3000 and the
  /// payable would still sit at 1500, when the user expects 1500/0.
  Future<String> postLabourPayment({
    required double amount,
    required String projectId,
    required String supplierId,
    required Account paidFrom,
    String? description,
  }) async {
    _assertNonEmpty(projectId, 'projectId');
    _assertNonEmpty(supplierId, 'supplierId');
    await _assertCashLike(paidFrom);

    final owed = await supplierPayableBalance(supplierId);

    // Full settlement: payment ≤ what we owe. One transaction settling the
    // payable, no new cost (cost was booked at credit time).
    if (owed >= amount - 0.01) {
      return _post(
        debitAccount: Accounts.supplierPayables,
        creditAccount: paidFrom,
        amount: amount,
        projectId: projectId,
        supplierId: supplierId,
        description: description,
      );
    }

    // Partial: settle the existing credit, then book the remainder as a
    // fresh direct labour cost. Two posts under the same description so the
    // ledger view shows a coherent payment.
    if (owed > 0.01) {
      await _post(
        debitAccount: Accounts.supplierPayables,
        creditAccount: paidFrom,
        amount: owed,
        projectId: projectId,
        supplierId: supplierId,
        description: description,
      );
      return _post(
        debitAccount: Accounts.labourCosts,
        creditAccount: paidFrom,
        amount: amount - owed,
        projectId: projectId,
        supplierId: supplierId,
        description: description,
      );
    }

    // No outstanding credit — direct labour cost like before.
    return _post(
      debitAccount: Accounts.labourCosts,
      creditAccount: paidFrom,
      amount: amount,
      projectId: projectId,
      supplierId: supplierId,
      description: description,
    );
  }

  /// Net amount we currently owe a single supplier (credits − debits on
  /// the Supplier Payables account, scoped to this supplier id). Positive
  /// = we still owe them; zero = settled; negative = we overpaid.
  Future<double> supplierPayableBalance(String supplierId) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(credit), 0) - COALESCE(SUM(debit), 0) AS bal '
      'FROM journal_entries '
      'WHERE account_id = ? AND supplier_id = ? AND is_deleted = 0',
      [Accounts.supplierPayables.id, supplierId],
    );
    return ((rows.first['bal'] as num?) ?? 0).toDouble();
  }

  /// Wages incurred but not yet paid. Posts Dr Labour Costs / Cr Supplier
  /// Payables — symmetric to [postMaterialBuy] but for labour.
  ///
  /// The cost hits the project ledger immediately (via Labour Costs); the
  /// payable to the worker shows up on their supplier ledger and is settled
  /// later by [postSupplierPay] when cash actually leaves.
  Future<String> postLabourCredit({
    required double amount,
    required String projectId,
    required String supplierId,
    String? description,
  }) {
    _assertNonEmpty(projectId, 'projectId');
    _assertNonEmpty(supplierId, 'supplierId');
    return _post(
      debitAccount: Accounts.labourCosts,
      creditAccount: Accounts.supplierPayables,
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
    _assertNonEmpty(supplierId, 'supplierId');
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
    _assertNonEmpty(projectId, 'projectId');
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
    _assertNonEmpty(projectId, 'projectId');
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
      {String? projectId,
      DateTime? from,
      DateTime? to,
      bool includeDeleted = false}) async {
    final where = StringBuffer('supplier_id = ?');
    final args = <Object>[supplierId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      // Inclusive upper bound: bump to next-day midnight so transactions
      // dated on `to` itself are included regardless of their time-of-day.
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
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
  /// running balance. Optional [from]/[to] filters narrow to a date window
  /// inclusive on both ends.
  Future<List<JournalEntry>> entriesForAccount(String accountId,
      {DateTime? from,
      DateTime? to,
      bool includeDeleted = false}) async {
    final where = StringBuffer('account_id = ?');
    final args = <Object>[accountId];
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Project ledger feed.
  ///
  /// `_post` tags BOTH legs of a balanced txn with the same `project_id`, so
  /// a naïve "where project_id = ?" returns the offsetting cash/payables row
  /// alongside the actual project leg — and the ledger view ends up
  /// double-counting (and rendering revenue as a fake debit). We filter to
  /// only the four accounts that actually represent project economics:
  ///
  ///   * Material Costs / Labour Costs — cost side (natural debit)
  ///   * Project Revenue / Service Fee Income — income side (natural credit)
  ///
  /// Consequences:
  ///   * Supplier Pay no longer appears in the project ledger (the cost was
  ///     already booked at Material Buy time; the payment is a cash-side
  ///     settlement, not a project cost event).
  ///   * Receive From Project / Service Fee land in the credit column and
  ///     properly reduce the project's net cost-side position.
  Future<List<JournalEntry>> entriesForProject(String projectId,
      {DateTime? from,
      DateTime? to,
      bool includeDeleted = false}) async {
    const projectAccountIds = <String>[
      'MATERIAL_COSTS',
      'LABOUR_COSTS',
      'PROJECT_REV',
      'SERVICE_FEE',
    ];
    final where = StringBuffer(
        'project_id = ? AND account_id IN (${projectAccountIds.map((_) => '?').join(', ')})');
    final args = <Object>[projectId, ...projectAccountIds];
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Wage ledger feed: every Labour Costs debit charged against this
  /// supplier (worker). Mirrors [entriesForProject]'s account-filter
  /// approach so payments to other suppliers don't leak in.
  Future<List<JournalEntry>> entriesForWorker(String supplierId,
      {DateTime? from,
      DateTime? to,
      bool includeDeleted = false}) async {
    final where = StringBuffer(
        'supplier_id = ? AND account_id = ? AND debit > 0');
    final args = <Object>[supplierId, Accounts.labourCosts.id];
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    if (!includeDeleted) where.write(' AND is_deleted = 0');
    final rows = await _db.query('journal_entries',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'created_at ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Comprehensive cash flow summary across every cash-like account
  /// (Cash + Supervisor Float + every user bank). Bucketed into operating
  /// vs financing activities so the report follows the FBR-style indirect
  /// cash-flow layout. Optional [from]/[to] window applies to all cash
  /// movements; the opening balance is the cash position right before
  /// [from] (or zero if no `from` is set).
  ///
  /// Categorisation rule (driven by the OTHER side of each cash leg):
  ///   * Operating inflow  ← Project Revenue, Service Fee Income credits
  ///   * Operating outflow ← Material Costs / Labour Costs debits, Supplier
  ///     Payables debits (settlements of trade liabilities)
  ///   * Financing outflow ← Personal / Daily Draw debits
  ///   * Other             ← anything else (opening balances etc.)
  /// Wallet transfers are ignored — the cash leaves one cash-like account
  /// and lands in another, so the consolidated cash position doesn't move.
  Future<CashFlowSummary> cashFlowSummary({DateTime? from, DateTime? to}) async {
    final cashIds = await cashLikeAccountIds();
    if (cashIds.isEmpty) return CashFlowSummary.empty;

    final placeholders = cashIds.map((_) => '?').join(', ');

    Future<double> openingBalance() async {
      if (from == null) return 0;
      final r = await _db.rawQuery(
        'SELECT COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0) AS bal '
        'FROM journal_entries '
        'WHERE is_deleted = 0 AND account_id IN ($placeholders) '
        'AND created_at < ?',
        [...cashIds, from.toUtc().toIso8601String()],
      );
      return ((r.first['bal'] as num?) ?? 0).toDouble();
    }

    // Pull every cash-leg row in the period and read its sibling on the same
    // transaction_id to discover what the cash exchanged for.
    final whereClauses = <String>[
      'is_deleted = 0',
      'account_id IN ($placeholders)',
    ];
    final args = <Object>[...cashIds];
    if (from != null) {
      whereClauses.add('created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      whereClauses.add('created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    final cashRows = await _db.rawQuery(
      'SELECT transaction_id, debit, credit FROM journal_entries '
      'WHERE ${whereClauses.join(' AND ')}',
      args,
    );

    double opIn = 0, opOut = 0, finOut = 0, other = 0;

    for (final row in cashRows) {
      final txnId = row['transaction_id'] as String;
      final dr = (row['debit'] as num).toDouble();
      final cr = (row['credit'] as num).toDouble();
      final delta = dr - cr; // + = cash in, − = cash out

      // Find the sibling (the non-cash leg of this transaction).
      final sibling = await _db.rawQuery(
        'SELECT account_id FROM journal_entries '
        'WHERE transaction_id = ? AND account_id NOT IN ($placeholders) '
        'AND is_deleted = 0 LIMIT 1',
        [txnId, ...cashIds],
      );
      if (sibling.isEmpty) {
        // Wallet transfer — both legs are cash-like, so consolidated cash
        // is unchanged. Skip entirely; surfacing them on the cash flow
        // statement was just noise.
        continue;
      }
      final otherAccount = sibling.first['account_id'] as String;

      switch (otherAccount) {
        case 'PROJECT_REV':
        case 'SERVICE_FEE':
          opIn += delta; // cash in from operations
        case 'MATERIAL_COSTS':
        case 'LABOUR_COSTS':
        case 'SUPPLIER_PAY':
          opOut += -delta; // outflow stored as positive number
        case 'PERSONAL_DRAW':
          finOut += -delta;
        case 'OWNERS_EQUITY':
          // Opening balance for a bank: counts as financing inflow if cash
          // came in, or financing outflow if money was drawn against equity.
          if (delta >= 0) {
            opIn += delta;
          } else {
            finOut += -delta;
          }
        default:
          other += delta;
      }
    }

    final opening = await openingBalance();
    return CashFlowSummary(
      openingCash: opening,
      operatingInflow: opIn,
      operatingOutflow: opOut,
      financingOutflow: finOut,
      otherNet: other,
    );
  }

  /// Single source of truth for revenue / cost figures used by both the
  /// Income Statement and the dashboard's Net Profit. Implements
  /// **Percentage-of-Completion (cost-recovery variant)** so a project
  /// payment received before the matching costs are incurred does **not**
  /// inflate profit — it sits as a customer-deposit liability instead.
  ///
  /// Recognition rules:
  ///   * **With-Material, in-progress** (not archived):
  ///       revenue_recognized = min(received, costs_to_date)
  ///       deposit_owed       = max(received - costs_to_date, 0)
  ///     i.e. cost-recovery — zero gross profit recognized until the project
  ///     is closed. This is conservative and avoids "fake profit" from
  ///     advance payments.
  ///   * **With-Material, closed** (archived): the contract is delivered,
  ///     so revenue = min(received, budget); any received over budget is a
  ///     deposit owed back to the customer.
  ///   * **Loss provision** (GAAP/IFRS rule): if costs exceed budget on any
  ///     project (active or closed), the excess is recognized **immediately**
  ///     as a separate cost line. Future losses must be booked the moment
  ///     they become probable, not deferred.
  ///   * **Labour-Rate**: unchanged — service fees are the only earned
  ///     income; everything else received sits as a deposit.
  ///
  /// Returns [IncomeFigures] including a list of projects flagged as
  /// at-risk (costs ≥ 80% of budget) so the UI can render loss warnings.
  Future<IncomeFigures> incomeFigures({
    DateTime? from,
    DateTime? to,
    String? projectId,
  }) async {
    // ── Load projects in scope ────────────────────────────────────────────
    final projWhere = projectId != null ? 'WHERE id = ?' : '';
    final projArgs = projectId != null ? <Object>[projectId] : <Object>[];
    final projRows = await _db.rawQuery(
      'SELECT id, name, model, budget, is_archived FROM projects $projWhere',
      projArgs,
    );

    double wmRevenue = 0;
    double wmDeposit = 0;
    double matCosts = 0;
    double labCosts = 0;
    double lossProvision = 0;
    double lrDeposit = 0;
    final atRisk = <ProjectAtRisk>[];

    for (final r in projRows) {
      final pid = r['id'] as String;
      final pname = (r['name'] as String?) ?? '';
      final pmodel = (r['model'] as String?) ?? '';
      final budget = (r['budget'] as num?)?.toDouble() ?? 0;
      final closed = ((r['is_archived'] as int?) ?? 0) == 1;

      final received = await creditBalance(Accounts.projectRevenue.id,
          projectId: pid, from: from, to: to);
      final mat = await accountBalance(Accounts.materialCosts.id,
          projectId: pid, from: from, to: to);
      final lab = await accountBalance(Accounts.labourCosts.id,
          projectId: pid, from: from, to: to);
      final costs = mat + lab;

      matCosts += mat;
      labCosts += lab;

      if (pmodel == 'with_material') {
        if (closed) {
          // Project complete → recognize full contract.
          if (budget > 0 && received > budget) {
            wmRevenue += budget;
            wmDeposit += received - budget;
          } else {
            wmRevenue += received;
          }
        } else {
          // PoC cost-recovery: only recognize revenue matched by costs.
          final recognized = received < costs ? received : costs;
          wmRevenue += recognized;
          if (received > recognized) wmDeposit += received - recognized;
        }
      } else {
        // Labour-Rate — existing logic: residual after service-fee
        // reclassification and customer-funded costs is deposit owed back.
        final net = received - costs;
        if (net > 0) lrDeposit += net;
      }

      // Loss provision — applies to every project model. If we've spent
      // more on this job than the budget allows, the excess is a loss
      // already in the bag, recognized immediately per FASB/IFRS.
      if (budget > 0 && costs > budget) {
        lossProvision += costs - budget;
      }

      // At-risk flag for the dashboard warning panel.
      if (budget > 0 && costs > 0) {
        final pct = costs / budget * 100;
        if (pct >= 80) {
          atRisk.add(ProjectAtRisk(
            projectId: pid,
            projectName: pname,
            budget: budget,
            costsToDate: costs,
            pctConsumed: pct,
            isOverBudget: costs > budget,
          ));
        }
      }
    }

    // Service fees are project-tagged, but the existing code summed them
    // globally when no project filter was active. Match that behaviour.
    final serviceFees = await creditBalance(Accounts.serviceFeeIncome.id,
        projectId: projectId, from: from, to: to);

    final personalDraw = projectId == null
        ? await accountBalance(Accounts.personalDraw.id, from: from, to: to)
        : 0.0;

    // Sort at-risk projects by severity (over-budget first, then by % consumed).
    atRisk.sort((a, b) {
      if (a.isOverBudget != b.isOverBudget) return a.isOverBudget ? -1 : 1;
      return b.pctConsumed.compareTo(a.pctConsumed);
    });

    return IncomeFigures(
      wmRevenue: wmRevenue,
      serviceFees: serviceFees,
      matCosts: matCosts,
      labCosts: labCosts,
      personalDraw: personalDraw,
      lrDeposit: lrDeposit,
      wmDeposit: wmDeposit,
      lossProvision: lossProvision,
      projectsAtRisk: atRisk,
    );
  }

  /// Sum(debit) - sum(credit). Always excludes soft-deleted rows. Optional
  /// [from]/[to] window applies inclusively to `created_at`.
  Future<double> accountBalance(String accountId,
      {String? projectId, DateTime? from, DateTime? to}) async {
    final where = StringBuffer('account_id = ? AND is_deleted = 0');
    final args = <Object>[accountId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0) AS bal '
      'FROM journal_entries WHERE ${where.toString()}',
      args,
    );
    return ((rows.first['bal'] as num?) ?? 0).toDouble();
  }

  Future<double> creditBalance(String accountId,
      {String? projectId, DateTime? from, DateTime? to}) async {
    final bal = await accountBalance(accountId,
        projectId: projectId, from: from, to: to);
    return -bal;
  }

  /// Sum of debits to a specific account, optionally filtered by project
  /// and/or date window.
  Future<double> sumDebits(String accountId,
      {String? projectId, DateTime? from, DateTime? to}) async {
    final where = StringBuffer('account_id = ? AND is_deleted = 0');
    final args = <Object>[accountId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) AS s FROM journal_entries WHERE ${where.toString()}',
      args,
    );
    return ((rows.first['s'] as num?) ?? 0).toDouble();
  }

  Future<double> sumCredits(String accountId,
      {String? projectId, DateTime? from, DateTime? to}) async {
    final where = StringBuffer('account_id = ? AND is_deleted = 0');
    final args = <Object>[accountId];
    if (projectId != null) {
      where.write(' AND project_id = ?');
      args.add(projectId);
    }
    if (from != null) {
      where.write(' AND created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND created_at < ?');
      args.add(to.add(const Duration(days: 1)).toUtc().toIso8601String());
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

  /// Same numbers `archiveProject`'s gate checks, exposed publicly so the
  /// reconciliation screen can render the "what's still wrong" message
  /// without duplicating the SQL.
  Future<({double supplierPayables, double ledgerNet, double serviceFeeBooked})>
      projectArchiveStatus(String projectId) async {
    Future<double> sum(String column, String accountId) async {
      final rows = await _db.rawQuery(
        'SELECT COALESCE(SUM($column),0) AS s FROM journal_entries '
        'WHERE account_id = ? AND project_id = ? AND is_deleted = 0',
        [accountId, projectId],
      );
      return ((rows.first['s'] as num?) ?? 0).toDouble();
    }

    final supplierPaid = await sum('debit', Accounts.supplierPayables.id);
    final supplierCredits = await sum('credit', Accounts.supplierPayables.id);
    final supplierPayables = supplierCredits - supplierPaid;

    final materialDr = await sum('debit', Accounts.materialCosts.id);
    final labourDr = await sum('debit', Accounts.labourCosts.id);
    final revenueCr = await sum('credit', Accounts.projectRevenue.id);
    final feeCr = await sum('credit', Accounts.serviceFeeIncome.id);
    final ledgerNet = (materialDr + labourDr) - (revenueCr + feeCr);

    return (
      supplierPayables: supplierPayables,
      ledgerNet: ledgerNet,
      // The screen uses serviceFeeBooked to know whether the
      // labour-rate fee reclassification has already been posted.
      serviceFeeBooked: feeCr,
    );
  }

  /// Total project outflow = material costs + labour costs for project.
  Future<double> projectOutflow(String projectId) async {
    final mat =
        await sumDebits(Accounts.materialCosts.id, projectId: projectId);
    final lab = await sumDebits(Accounts.labourCosts.id, projectId: projectId);
    return mat + lab;
  }

  /// Closing snapshot for a Labour-Rate project.
  ///
  /// In the labour-rate model the contractor is a pass-through:
  ///   * `customerPaid`  — total `Project Revenue` credits (cash from
  ///     customer over the life of the project).
  ///   * `totalSpent`    — total Material + Labour cost debits (what we
  ///     spent on the customer's behalf).
  ///   * `serviceFee`    — `totalSpent × feePercent / 100`, the contractor's
  ///     earnings on this job.
  ///   * `netToSettle`   — `(customerPaid − serviceFee) − totalSpent`.
  ///       positive → refund customer the surplus
  ///       negative → customer owes us the deficit (already includes fee)
  Future<LabourRateClose> labourRateCloseSummary(
      String projectId, double feePercent) async {
    final customerPaid =
        await sumCredits(Accounts.projectRevenue.id, projectId: projectId);
    final totalSpent = await projectOutflow(projectId);
    final serviceFee = totalSpent * feePercent / 100;
    final customerFundsAvail = customerPaid - serviceFee;
    final netToSettle = customerFundsAvail - totalSpent;
    return LabourRateClose(
      customerPaid: customerPaid,
      totalSpent: totalSpent,
      feePercent: feePercent,
      serviceFee: serviceFee,
      netToSettle: netToSettle,
    );
  }

  /// Posts the labour-rate service fee at project close as a non-cash
  /// reclassification: Dr Project Revenue / Cr Service Fee Income, both
  /// tagged with `projectId`. Cash position is unaffected — the fee just
  /// re-buckets a slice of recognized customer revenue into the
  /// contractor's own income line so the Income Statement separates
  /// "money handled for the customer" from "earnings".
  Future<String> postProjectServiceFee({
    required String projectId,
    required double amount,
    String? description,
  }) {
    _assertNonEmpty(projectId, 'projectId');
    return _post(
      debitAccount: Accounts.projectRevenue,
      creditAccount: Accounts.serviceFeeIncome,
      amount: amount,
      projectId: projectId,
      description: description ?? 'Service fee on project close',
    );
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

  /// Aging — projects that have not paid us yet. For each project we walk
  /// the journal in chronological order:
  ///   * Material/Labour Costs debits (project_id) = "we spent on the
  ///     customer's behalf" → contributes to the open balance owed.
  ///   * Project Revenue credits (project_id) = "customer paid" → consumes
  ///     the open balance FIFO.
  /// Whatever is left after the FIFO match is bucketed by age. Mirrors
  /// `aging()` so the screen can render with the same widgets.
  Future<AgingReport> agingProjectReceivables({DateTime? asOf}) async {
    final now = (asOf ?? DateTime.now()).toUtc();
    // Pull every cost & revenue row tagged with a project, in time order.
    final rows = await _db.rawQuery(
      'SELECT project_id, account_id, debit, credit, created_at '
      'FROM journal_entries '
      'WHERE is_deleted = 0 AND project_id IS NOT NULL '
      'AND account_id IN (?, ?, ?) '
      'ORDER BY created_at ASC',
      [
        Accounts.materialCosts.id,
        Accounts.labourCosts.id,
        Accounts.projectRevenue.id,
      ],
    );

    final byProject = <String, List<_OpenInvoice>>{};
    for (final r in rows) {
      final projectId = r['project_id'] as String;
      final accountId = r['account_id'] as String;
      final debit = (r['debit'] as num).toDouble();
      final credit = (r['credit'] as num).toDouble();
      final created = DateTime.parse(r['created_at'] as String);

      final queue = byProject.putIfAbsent(projectId, () => []);
      if (accountId == Accounts.materialCosts.id ||
          accountId == Accounts.labourCosts.id) {
        // Cost incurred → customer owes us this much.
        if (debit > 0) {
          queue.add(_OpenInvoice(date: created, remaining: debit));
        }
      } else if (accountId == Accounts.projectRevenue.id) {
        // Customer paid → consume open balance FIFO.
        var pay = credit;
        while (pay > 0 && queue.isNotEmpty) {
          final head = queue.first;
          if (head.remaining <= pay) {
            pay -= head.remaining;
            queue.removeAt(0);
          } else {
            head.remaining -= pay;
            pay = 0;
          }
        }
      }
    }

    final lines = <AgingLine>[];
    byProject.forEach((projectId, queue) {
      var b0 = 0.0, b30 = 0.0, b60 = 0.0, b90 = 0.0;
      for (final inv in queue) {
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
          partyId: projectId,
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

  /// Aging — suppliers we have OVERPAID (negative payable). For each
  /// supplier:
  ///   * Supplier Payables debits = payments to the supplier (advance) →
  ///     contributes to "they owe us".
  ///   * Supplier Payables credits = bills incurred → consume the advance
  ///     FIFO.
  /// What's left is the unmatched advance, bucketed by age. The standard
  /// payables aging already covers the opposite direction.
  Future<AgingReport> agingSupplierOverpayment({DateTime? asOf}) async {
    final now = (asOf ?? DateTime.now()).toUtc();
    final rows = await _db.query(
      'journal_entries',
      where: 'account_id = ? AND is_deleted = 0',
      whereArgs: [Accounts.supplierPayables.id],
      orderBy: 'created_at ASC',
    );

    final bySupplier = <String, List<_OpenInvoice>>{};
    for (final row in rows) {
      final je = JournalEntry.fromMap(row);
      final supplierId = je.supplierId;
      if (supplierId == null) continue;
      final queue = bySupplier.putIfAbsent(supplierId, () => []);
      if (je.debit > 0) {
        // Payment to supplier — they hold our money.
        queue.add(_OpenInvoice(date: je.createdAt, remaining: je.debit));
      } else if (je.credit > 0) {
        var pay = je.credit;
        while (pay > 0 && queue.isNotEmpty) {
          final head = queue.first;
          if (head.remaining <= pay) {
            pay -= head.remaining;
            queue.removeAt(0);
          } else {
            head.remaining -= pay;
            pay = 0;
          }
        }
      }
    }

    final lines = <AgingLine>[];
    bySupplier.forEach((supplierId, queue) {
      var b0 = 0.0, b30 = 0.0, b60 = 0.0, b90 = 0.0;
      for (final inv in queue) {
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
          partyId: supplierId,
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

  /// Sum of grand totals across project-side and supplier-side
  /// receivables — exposed for the dashboard tile so it doesn't have to
  /// re-run the FIFO calc just to show one number.
  Future<({double projectsOwed, double suppliersOverpaid})>
      receivablesTotals() async {
    final p = await agingProjectReceivables();
    final s = await agingSupplierOverpayment();
    return (
      projectsOwed: p.grandTotal,
      suppliersOverpaid: s.grandTotal,
    );
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
    final byMaterial = <String, double>{};
    for (final r in matRows) {
      final label = resolveMaterialLabel(r['material_type'] as String);
      byMaterial[label] = (byMaterial[label] ?? 0) + (r['s'] as num).toDouble();
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

  /// Time-series of unit rates per material label from `material_inventory`,
  /// for the last `monthsBack` months. Each entry is `(date, rate)`.
  Future<Map<String, List<PricePoint>>> priceTrend(
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
    final out = <String, List<PricePoint>>{};
    for (final r in rows) {
      final label = resolveMaterialLabel(r['material_type'] as String);
      out
          .putIfAbsent(label, () => [])
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

  // -------------------- Cash Runway --------------------

  /// Average daily material + labour spend over the last [daysBack] days.
  /// Returns 0 when there is no spending history (avoids divide-by-zero at
  /// the call site).
  /// Average burn rate over the last [daysBack] days, computed across the
  /// **days that actually had cost activity** rather than all calendar days
  /// in the window. This is the more common professional approach: it
  /// reflects what you spend on a typical spending day, instead of getting
  /// dragged toward zero by inactive days.
  ///
  /// Example: Rs 18,000 spent on a single day in the last 30 →
  /// burn = 18,000 / 1 = Rs 18,000/day (was 600/day under the old
  /// total ÷ 30 formula).
  Future<double> averageDailyExpense({int daysBack = 30}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: daysBack))
        .toIso8601String();
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(debit), 0) AS total, '
      'COUNT(DISTINCT DATE(created_at)) AS days '
      'FROM journal_entries '
      'WHERE is_deleted = 0 AND account_id IN (?, ?) AND debit > 0 '
      'AND created_at >= ?',
      [Accounts.materialCosts.id, Accounts.labourCosts.id, cutoff],
    );
    final total = ((rows.first['total'] as num?) ?? 0).toDouble();
    final activeDays = ((rows.first['days'] as num?) ?? 0).toInt();
    if (activeDays == 0) return 0;
    return total / activeDays;
  }

  // -------------------- Supplier-wise Spending --------------------

  /// Total material + labour costs grouped by supplier, sorted highest first.
  /// Optional [daysBack] restricts to the last N days.
  Future<List<SupplierSpend>> supplierSpending({int? daysBack}) async {
    final args = <Object>[Accounts.materialCosts.id, Accounts.labourCosts.id];
    final where = StringBuffer(
      'account_id IN (?, ?) AND is_deleted = 0 AND debit > 0 AND supplier_id IS NOT NULL',
    );
    if (daysBack != null) {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(Duration(days: daysBack))
          .toIso8601String();
      where.write(' AND created_at >= ?');
      args.add(cutoff);
    }
    final rows = await _db.rawQuery(
      'SELECT supplier_id, SUM(debit) AS total FROM journal_entries '
      'WHERE ${where.toString()} GROUP BY supplier_id ORDER BY total DESC',
      args,
    );
    return rows
        .map((r) => SupplierSpend(
              supplierId: r['supplier_id'] as String,
              total: (r['total'] as num).toDouble(),
            ))
        .toList();
  }

  // -------------------- Daily Spend --------------------

  /// Material + labour costs for a project grouped by calendar day (UTC date),
  /// ordered oldest → newest. Covers the full project lifetime.
  Future<List<DailySpend>> projectDailySpend(String projectId) async {
    final rows = await _db.rawQuery(
      'SELECT DATE(created_at) AS day, SUM(debit) AS total '
      'FROM journal_entries '
      'WHERE is_deleted = 0 AND project_id = ? '
      'AND account_id IN (?, ?) AND debit > 0 '
      'GROUP BY day ORDER BY day ASC',
      [projectId, Accounts.materialCosts.id, Accounts.labourCosts.id],
    );
    return rows
        .map((r) => DailySpend(
              date: DateTime.parse(r['day'] as String),
              amount: (r['total'] as num).toDouble(),
            ))
        .toList();
  }

  /// Material + labour costs across ALL projects grouped by calendar day (UTC),
  /// covering the last [daysBack] days. Used by the dashboard spending strip.
  Future<List<DailySpend>> overallDailySpend({int daysBack = 7}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: daysBack))
        .toIso8601String();
    final rows = await _db.rawQuery(
      'SELECT DATE(created_at) AS day, SUM(debit) AS total '
      'FROM journal_entries '
      'WHERE is_deleted = 0 '
      'AND account_id IN (?, ?) AND debit > 0 '
      'AND created_at >= ? '
      'GROUP BY day ORDER BY day ASC',
      [Accounts.materialCosts.id, Accounts.labourCosts.id, cutoff],
    );
    return rows
        .map((r) => DailySpend(
              date: DateTime.parse(r['day'] as String),
              amount: (r['total'] as num).toDouble(),
            ))
        .toList();
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

/// Result of [LedgerRepository.incomeFigures]. Single source of truth for
/// every "what's our P&L?" surface (Income Statement, dashboard Net Profit).
class IncomeFigures {
  /// Recognized contract revenue from With-Material projects, computed via
  /// cost-recovery PoC for active jobs and full contract recognition for
  /// closed jobs.
  final double wmRevenue;
  final double serviceFees;
  final double matCosts;
  final double labCosts;
  final double personalDraw;
  /// Customer money received but not yet earned — sits as a liability.
  final double lrDeposit;
  final double wmDeposit;
  /// Sum of (costs - budget) across every project where costs exceeded
  /// budget. Recognized as an immediate cost line per FASB/IFRS loss
  /// provision rules.
  final double lossProvision;
  /// Projects whose cost-to-date is ≥ 80% of budget. Sorted with already-
  /// over-budget jobs first, then by % consumed descending.
  final List<ProjectAtRisk> projectsAtRisk;

  const IncomeFigures({
    required this.wmRevenue,
    required this.serviceFees,
    required this.matCosts,
    required this.labCosts,
    required this.personalDraw,
    required this.lrDeposit,
    required this.wmDeposit,
    required this.lossProvision,
    required this.projectsAtRisk,
  });

  double get totalIncome => wmRevenue + serviceFees;
  double get totalCosts => matCosts + labCosts + personalDraw + lossProvision;
  double get netProfit => totalIncome - totalCosts;
  double get totalDeposit => lrDeposit + wmDeposit;
}

/// One project's risk snapshot for the dashboard's "Projects at Risk" panel.
class ProjectAtRisk {
  final String projectId;
  final String projectName;
  final double budget;
  final double costsToDate;
  /// 0..100+ — values above 100 mean already over budget.
  final double pctConsumed;
  final bool isOverBudget;

  const ProjectAtRisk({
    required this.projectId,
    required this.projectName,
    required this.budget,
    required this.costsToDate,
    required this.pctConsumed,
    required this.isOverBudget,
  });
}

/// Indirect-method cash flow summary across every cash-like account.
///
/// All `*flow` and `*Outflow` numbers are stored as positive values;
/// the sign is implicit from the field name. `netChange` walks
/// opening cash → closing cash through the bucketed activity totals.
class CashFlowSummary {
  /// Cash position at the moment the period opened (sum of all cash-like
  /// account balances right before `from`). Zero when no `from` is set.
  final double openingCash;
  final double operatingInflow;
  final double operatingOutflow;
  final double financingOutflow;
  /// Catch-all for cash legs whose sibling didn't land in any of the
  /// canonical buckets — e.g. legacy data, manual journal corrections.
  final double otherNet;

  const CashFlowSummary({
    required this.openingCash,
    required this.operatingInflow,
    required this.operatingOutflow,
    required this.financingOutflow,
    required this.otherNet,
  });

  static const empty = CashFlowSummary(
    openingCash: 0,
    operatingInflow: 0,
    operatingOutflow: 0,
    financingOutflow: 0,
    otherNet: 0,
  );

  double get netOperating => operatingInflow - operatingOutflow;
  double get netFinancing => -financingOutflow;
  double get netChange => netOperating + netFinancing + otherNet;
  double get closingCash => openingCash + netChange;
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
  /// Keyed by the human-readable material label (e.g. "Cement"). User-defined
  /// types appear here verbatim; legacy enum-name rows are normalized via
  /// [resolveMaterialLabel].
  final Map<String, double> materialByType;
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

class DailySpend {
  final DateTime date;
  final double amount;
  const DailySpend({required this.date, required this.amount});
}

class SupplierSpend {
  final String supplierId;
  final double total;
  const SupplierSpend({required this.supplierId, required this.total});
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

/// Settlement snapshot returned by [LedgerRepository.labourRateCloseSummary].
///
/// Sign convention on [netToSettle]:
///   * Positive → contractor is holding the customer's surplus → refund it.
///   * Negative → spending overran customer's deposits → customer owes us
///     this amount (deficit + service fee, packed into one number).
class LabourRateClose {
  final double customerPaid;
  final double totalSpent;
  final double feePercent;
  final double serviceFee;
  final double netToSettle;

  const LabourRateClose({
    required this.customerPaid,
    required this.totalSpent,
    required this.feePercent,
    required this.serviceFee,
    required this.netToSettle,
  });

  /// Amount the contractor has to refund (0 when the customer underpaid).
  double get refundToCustomer => netToSettle > 0 ? netToSettle : 0;

  /// Amount the customer still owes (0 when overpaid). Already includes
  /// the service fee in the deficit case.
  double get customerOwesUs => netToSettle < 0 ? -netToSettle : 0;
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
