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
  }) {
    _assertCashLike(paidFrom);
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
  }) {
    _assertCashLike(paidFrom);
    return _post(
      debitAccount: Accounts.supplierPayables,
      creditAccount: paidFrom,
      amount: amount,
      supplierId: supplierId,
      projectId: projectId,
      description: description,
    );
  }

  Future<String> postClientBilling({
    required double amount,
    required String customerId,
    required String projectId,
    String? description,
  }) =>
      _post(
        debitAccount: Accounts.clientReceivables,
        creditAccount: Accounts.projectRevenue,
        amount: amount,
        projectId: projectId,
        customerId: customerId,
        description: description,
      );

  Future<String> postReceivePayment({
    required double amount,
    required String customerId,
    required Account receivedInto,
    String? description,
    String? projectId,
  }) {
    _assertCashLike(receivedInto);
    return _post(
      debitAccount: receivedInto,
      creditAccount: Accounts.clientReceivables,
      amount: amount,
      customerId: customerId,
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
  }) {
    _assertCashLike(from);
    _assertCashLike(to);
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
  }) {
    _assertCashLike(paidFrom);
    return _post(
      debitAccount: Accounts.personalDraw,
      creditAccount: paidFrom,
      amount: amount,
      description: description,
    );
  }

  /// Service fee for Labour-Rate model (spec section 2 / interim fees).
  Future<String> postServiceFee({
    required double amount,
    required String projectId,
    required Account receivedInto,
    String? description,
  }) {
    _assertCashLike(receivedInto);
    return _post(
      debitAccount: receivedInto,
      creditAccount: Accounts.serviceFeeIncome,
      amount: amount,
      projectId: projectId,
      description: description,
    );
  }

  void _assertCashLike(Account a) {
    if (!Accounts.cashLikeAccounts.contains(a)) {
      throw ArgumentError('Account ${a.id} is not a cash/bank account.');
    }
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
            timestamp: now,
          ).toMap());
    });
  }

  /// Restore a soft-deleted transaction.
  Future<void> restoreTransaction(String transactionId,
      {String? note}) async {
    final rows = await _db.query('journal_entries',
        where: 'transaction_id = ? AND is_deleted = 1',
        whereArgs: [transactionId]);
    if (rows.isEmpty) return;
    final now = DateTime.now().toUtc();

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
            timestamp: now,
          ).toMap());
    });
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

  /// Project reconciliation snapshot (spec section 1).
  ///
  /// Returns customer billings, supplier paid, and outstanding payables for
  /// the project. The reconciliation rule is:
  ///   customerInflow == supplierPaid + supplierPayables
  Future<ProjectReconciliation> reconcileProject(String projectId) async {
    // Customer inflow == billings posted to CLIENT_RECV with this project.
    final customerInflow =
        await sumDebits(Accounts.clientReceivables.id, projectId: projectId);

    // Supplier paid == debits to SUPPLIER_PAY with this project.
    final supplierPaid =
        await sumDebits(Accounts.supplierPayables.id, projectId: projectId);

    // Supplier payables outstanding for this project = credits - debits.
    final credits = await sumCredits(Accounts.supplierPayables.id,
        projectId: projectId);
    final supplierPayables = credits - supplierPaid;

    return ProjectReconciliation(
      customerInflow: customerInflow,
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

class ProjectReconciliation {
  final double customerInflow;
  final double supplierPaid;
  final double supplierPayables;

  const ProjectReconciliation({
    required this.customerInflow,
    required this.supplierPaid,
    required this.supplierPayables,
  });

  /// Spec rule: inflow == paid + payables. Tolerance for floating-point.
  bool get isBalanced =>
      (customerInflow - (supplierPaid + supplierPayables)).abs() < 0.01;

  double get imbalance =>
      customerInflow - (supplierPaid + supplierPayables);
}
