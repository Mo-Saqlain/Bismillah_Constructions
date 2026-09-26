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

  test('Backdated transaction records correct custom createdAt timestamp', () async {
    final project = await entityRepo.createProject(
      name: 'Old Plaza',
      model: ProjectModel.withMaterial,
      budget: 1000000,
    );
    final supplier = await entityRepo.createSupplier(name: 'Past Cement');

    // Post a backdated material buy for August 15, 2026
    final backdate = DateTime(2026, 8, 15, 10, 30);
    final txnId = await ledgerRepo.postMaterialBuy(
      amount: 45000,
      projectId: project.id,
      supplierId: supplier.id,
      description: 'Backdated Cement Buy',
      createdAt: backdate,
    );

    final entries = await ledgerRepo.allEntries();
    expect(entries, isNotEmpty);
    final match = entries.firstWhere((e) => e.transactionId == txnId);
    expect(match.createdAt.year, equals(2026));
    expect(match.createdAt.month, equals(8));
    expect(match.createdAt.day, equals(15));
  });
}
