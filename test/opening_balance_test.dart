import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bismillah_constructions/shared/core/constants.dart';
import 'package:bismillah_constructions/shared/data/db/local_db.dart';
import 'package:bismillah_constructions/shared/data/models/project.dart';
import 'package:bismillah_constructions/shared/data/repositories/entity_repository.dart';
import 'package:bismillah_constructions/shared/data/repositories/ledger_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late EntityRepository entityRepo;
  late LedgerRepository ledgerRepo;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 22,
      onCreate: (d, v) async {
        await LocalDb.instance.applySchemaForTests(d);
      },
    );
    entityRepo = EntityRepository(db);
    ledgerRepo = LedgerRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Supplier positive opening balance creates payable balance (we owe supplier)', () async {
    final supplier = await entityRepo.createSupplier(name: 'ABC Cement');

    // Positive 25,000 opening balance => We owe ABC Cement 25,000
    await ledgerRepo.postSupplierOpeningBalance(
      supplierId: supplier.id,
      amount: 25000,
    );

    final balance = await ledgerRepo.supplierPayableBalance(supplier.id);
    expect(balance, equals(25000));
  });

  test('Supplier negative opening balance creates credit balance (advance paid)', () async {
    final supplier = await entityRepo.createSupplier(name: 'XYZ Steel');

    // Negative -10,000 opening balance => We gave advance of 10,000 to XYZ Steel
    await ledgerRepo.postSupplierOpeningBalance(
      supplierId: supplier.id,
      amount: -10000,
    );

    final balance = await ledgerRepo.supplierPayableBalance(supplier.id);
    expect(balance, equals(-10000));
  });

  test('Project positive opening balance posts initial spend/cost', () async {
    final project = await entityRepo.createProject(
      name: 'Site A Plaza',
      model: ProjectModel.withMaterial,
      budget: 500000,
    );

    // Positive 50,000 opening balance => Initial spend on project
    await ledgerRepo.postProjectOpeningBalance(
      projectId: project.id,
      amount: 50000,
    );

    final snap = await ledgerRepo.projectSnapshot(project.id);
    expect(snap.spent, equals(50000));
  });

  test('Project negative opening balance posts customer advance/deposit', () async {
    final project = await entityRepo.createProject(
      name: 'Villa B',
      model: ProjectModel.withMaterial,
      budget: 1000000,
    );

    // Negative -150,000 opening balance => Customer advance received before app adoption
    await ledgerRepo.postProjectOpeningBalance(
      projectId: project.id,
      amount: -150000,
    );

    final snap = await ledgerRepo.projectSnapshot(project.id);
    expect(snap.received, equals(150000));
  });
}
