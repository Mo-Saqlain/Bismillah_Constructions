import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../models/bank.dart';
import '../models/change_log.dart';
import '../models/counter_entity.dart';
import '../models/material_item.dart';
import '../models/party.dart';
import '../models/project.dart';

const _uuid = Uuid();

class EntityRepository {
  EntityRepository(this._db);
  final Database _db;

  // ---- Projects ----

  Future<Project> createProject({
    required String name,
    required ProjectModel model,
    String? customerId,
    String? siteAddress,
    double? budget,
    String? projectManager,
    double? serviceFeePercent,
  }) async {
    final p = Project(
      id: _uuid.v4(),
      name: name.trim(),
      model: model,
      status: ProjectStatus.active,
      createdAt: DateTime.now().toUtc(),
      customerId: customerId,
      siteAddress:
          siteAddress?.trim().isEmpty == true ? null : siteAddress?.trim(),
      budget: budget,
      projectManager:
          projectManager?.trim().isEmpty == true ? null : projectManager?.trim(),
      serviceFeePercent: serviceFeePercent,
    );
    await _db.insert('projects', p.toMap());
    return p;
  }

  Future<List<Project>> projects(
      {bool activeOnly = false, bool includeArchived = false}) async {
    final clauses = <String>[];
    final args = <Object>[];
    if (activeOnly) {
      clauses.add('status = ?');
      args.add(ProjectStatus.active.db);
    }
    if (!includeArchived) {
      clauses.add('is_archived = 0');
    }
    final rows = await _db.query(
      'projects',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: clauses.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<List<Project>> archivedProjects() async {
    final rows = await _db.query(
      'projects',
      where: 'is_archived = 1',
      orderBy: 'archived_at DESC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> project(String id) async {
    final rows = await _db.query('projects', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }

  Future<void> updateProjectStatus(String id, ProjectStatus status) async {
    await _db.update('projects', {'status': status.db},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateProjectServiceFee(String id, double? percent) async {
    await _db.update('projects', {'service_fee_percent': percent},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-archive: preserves data, removes from active lists. Logged.
  Future<void> archiveProject(String id, {String? note}) async {
    final p = await project(id);
    if (p == null) return;
    final now = DateTime.now().toUtc();
    await _db.transaction((txn) async {
      await txn.update(
        'projects',
        {'is_archived': 1, 'archived_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
          'change_log',
          ChangeLog(
            id: _uuid.v4(),
            entityType: 'project',
            entityId: id,
            action: ChangeAction.archive,
            originalData: jsonEncode(p.toMap()),
            note: note,
            timestamp: now,
          ).toMap());
    });
  }

  Future<void> unarchiveProject(String id) async {
    final p = await project(id);
    if (p == null) return;
    final now = DateTime.now().toUtc();
    await _db.transaction((txn) async {
      await txn.update(
        'projects',
        {'is_archived': 0, 'archived_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
          'change_log',
          ChangeLog(
            id: _uuid.v4(),
            entityType: 'project',
            entityId: id,
            action: ChangeAction.unarchive,
            originalData: jsonEncode(p.toMap()),
            timestamp: now,
          ).toMap());
    });
  }

  // ---- Customers ----

  Future<Party> createCustomer({
    required String name,
    String? phone,
    String? ntnCnic,
    String? address,
    double? creditLimit,
  }) async {
    final p = Party(
      id: _uuid.v4(),
      name: name.trim(),
      phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
      createdAt: DateTime.now().toUtc(),
      ntnCnic: ntnCnic?.trim().isEmpty == true ? null : ntnCnic?.trim(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      creditLimit: creditLimit,
    );
    await _db.insert('customers', p.toCustomerMap());
    return p;
  }

  Future<List<Party>> customers() async {
    final rows = await _db.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Party.fromMap).toList();
  }

  Future<Party?> customer(String id) async {
    final rows =
        await _db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Party.fromMap(rows.first);
  }

  // ---- Suppliers ----

  Future<Party> createSupplier({
    required String name,
    String? phone,
    SupplierCategory? category,
    String? taxStatus,
    String? bankDetails,
  }) async {
    final p = Party(
      id: _uuid.v4(),
      name: name.trim(),
      phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
      createdAt: DateTime.now().toUtc(),
      category: category,
      taxStatus: taxStatus?.trim().isEmpty == true ? null : taxStatus?.trim(),
      bankDetails:
          bankDetails?.trim().isEmpty == true ? null : bankDetails?.trim(),
    );
    await _db.insert('suppliers', p.toSupplierMap());
    return p;
  }

  Future<List<Party>> suppliers() async {
    final rows = await _db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Party.fromMap).toList();
  }

  Future<Party?> supplier(String id) async {
    final rows =
        await _db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Party.fromMap(rows.first);
  }

  // ---- Banks ----

  Future<Bank> createBank({required String name, String? accountNo}) async {
    final b = Bank(
      id: _uuid.v4(),
      name: name.trim(),
      accountNo: accountNo?.trim().isEmpty == true ? null : accountNo?.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    await _db.insert('banks', b.toMap());
    return b;
  }

  Future<List<Bank>> banks() async {
    final rows = await _db.query('banks', orderBy: 'name COLLATE NOCASE');
    return rows.map(Bank.fromMap).toList();
  }

  // ---- Counter Entities ----

  Future<CounterEntity> createCounterEntity({
    required String name,
    required CounterEntityType type,
    double amount = 0,
  }) async {
    final e = CounterEntity(
      id: _uuid.v4(),
      name: name.trim(),
      type: type,
      amount: amount,
      createdAt: DateTime.now().toUtc(),
    );
    await _db.insert('counter_entities', e.toMap());
    return e;
  }

  Future<List<CounterEntity>> counterEntities() async {
    final rows =
        await _db.query('counter_entities', orderBy: 'name COLLATE NOCASE');
    return rows.map(CounterEntity.fromMap).toList();
  }

  Future<void> updateCounterEntityAmount(String id, double amount) async {
    await _db.update('counter_entities', {'amount': amount},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---- Material Inventory ----

  Future<MaterialItem> logMaterialPurchase({
    required String projectId,
    required String supplierId,
    String? transactionId,
    required MaterialType materialType,
    required double quantity,
    required double rate,
  }) async {
    final totalCost = MaterialItem.computeTotal(materialType, quantity, rate);
    final item = MaterialItem(
      id: _uuid.v4(),
      projectId: projectId,
      supplierId: supplierId,
      transactionId: transactionId,
      materialType: materialType,
      unit: materialType.defaultUnit,
      quantity: quantity,
      rate: rate,
      totalCost: totalCost,
      txnType: MaterialTxnType.purchase,
      createdAt: DateTime.now().toUtc(),
    );
    await _db.insert('material_inventory', item.toMap());
    return item;
  }

  Future<List<MaterialItem>> materialInventory({String? projectId}) async {
    final rows = await _db.query(
      'material_inventory',
      where: projectId != null ? 'project_id = ?' : null,
      whereArgs: projectId != null ? [projectId] : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(MaterialItem.fromMap).toList();
  }

  // ---- Settings ----

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    await _db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- Change Log ----

  Future<List<ChangeLog>> changeLog({String? entityType, int? limit}) async {
    final rows = await _db.query(
      'change_log',
      where: entityType == null ? null : 'entity_type = ?',
      whereArgs: entityType == null ? null : [entityType],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(ChangeLog.fromMap).toList();
  }

  Future<void> logChange({
    required String entityType,
    required String entityId,
    required ChangeAction action,
    Map<String, Object?>? originalData,
    Map<String, Object?>? newData,
    String? note,
  }) async {
    await _db.insert(
        'change_log',
        ChangeLog(
          id: _uuid.v4(),
          entityType: entityType,
          entityId: entityId,
          action: action,
          originalData:
              originalData == null ? null : jsonEncode(originalData),
          newData: newData == null ? null : jsonEncode(newData),
          note: note,
          timestamp: DateTime.now().toUtc(),
        ).toMap());
  }
}
