// Generates a stress-test SQLite database with realistic dummy data
// spread across the last 12 months. Run from the package root:
//
//   flutter test tool/generate_stress_db.dart
//
// (Uses `flutter test` so the `sqflite_common_ffi` engine and the
// production Dart code path are available without spinning up a UI.)
//
// Writes `output/stress_test.db` in the package root. Transfer to
// your phone (USB / WhatsApp / Drive) and import via:
//
//   Settings → Backup & Export → Import backup → pick the .db file
//   → restart the app.
//
// The output file is a real SQLite v3 database with the production
// v16 schema applied — the app's import validator (SQLite-header
// check) passes, and every row was inserted via the production
// repositories so all invariants (double-entry, FK linkage,
// material_inventory mirror) are intact.
//
// `flutter test tool/verify_stress_db.dart` after generation prints
// the row counts and confirms the double-entry sum balances.

// This tool is dev infrastructure that drives the production schema
// the same way unit tests do, so calls into
// `LocalDb.applySchemaForTests` are intentional and not a bug.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:math';

import 'package:bismillah_constructions/core/constants.dart';
import 'package:bismillah_constructions/data/db/local_db.dart';
import 'package:bismillah_constructions/data/models/bank.dart';
import 'package:bismillah_constructions/data/models/follow_up.dart';
import 'package:bismillah_constructions/data/models/labour_type_def.dart';
import 'package:bismillah_constructions/data/models/material_type_def.dart';
import 'package:bismillah_constructions/data/models/note.dart';
import 'package:bismillah_constructions/data/models/party.dart';
import 'package:bismillah_constructions/data/models/project.dart';
import 'package:bismillah_constructions/data/repositories/entity_repository.dart';
import 'package:bismillah_constructions/data/repositories/ledger_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─── Scale knobs ────────────────────────────────────────────────────
//
// Tuned to give every report something interesting to render without
// taking minutes to seed. Bump these if you want a heavier load.
const int kProjectCount = 14;
const int kSupplierCount = 40;
const int kBankCount = 5;
const int kMaterialTypeCount = 18;
const int kLabourTypeCount = 10;
const int kTransactionCount = 1800;
const int kNoteCount = 80;
const int kFollowUpCount = 40;

// Spread `created_at` over this many days going backward from now,
// so the Monthly P&L Trend has a full 12-month picture.
const int kHistoryDays = 380;

// Deterministic seed — re-running produces the same DB.
final _rng = Random(0xB15);

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final scriptDir = p.dirname(Platform.script.toFilePath());
  final outDir = Directory(p.join(scriptDir, 'output'));
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final outPath = p.join(outDir.path, 'stress_test.db');
  final outFile = File(outPath);
  if (outFile.existsSync()) outFile.deleteSync();

  final db = await databaseFactory.openDatabase(
    outPath,
    options: OpenDatabaseOptions(version: 16),
  );

  // Apply the production v16 schema in one shot.
  await LocalDb.instance.applySchemaForTests(db);

  // Device id row — the audit log expects one per install.
  await db.insert('app_settings', {
    'key': 'device_id',
    'value': 'stress-test-device-${_rng.nextInt(1 << 30)}',
  });

  final entityRepo = EntityRepository(db);
  final ledgerRepo = LedgerRepository(db);

  stdout.writeln('Seeding stress-test DB at $outPath');

  final materialTypes = await _seedMaterialTypes(entityRepo);
  final labourTypes = await _seedLabourTypes(entityRepo);
  stdout.writeln(
      '  catalogs: ${materialTypes.length} materials, ${labourTypes.length} labour types');

  final banks = await _seedBanks(entityRepo);
  final suppliers = await _seedSuppliers(entityRepo);
  final projects = await _seedProjects(entityRepo);
  stdout.writeln(
      '  entities: ${banks.length} banks, ${suppliers.length} suppliers, '
      '${projects.length} projects');

  // Opening balances on each bank so the books start with real cash.
  for (final b in banks) {
    final openingAmount = (250000 + _rng.nextInt(2_500_000)).toDouble();
    await ledgerRepo.postOpeningBalance(
      bankAccount: Account(b.id, b.name, AccountType.asset),
      amount: openingAmount,
    );
  }
  stdout.writeln('  opening balances: ${banks.length} entries');

  await _seedTransactions(
    db: db,
    entityRepo: entityRepo,
    ledgerRepo: ledgerRepo,
    projects: projects,
    suppliers: suppliers,
    banks: banks,
    materialTypes: materialTypes,
  );

  await _seedNotes(entityRepo, projects: projects, suppliers: suppliers);
  await _seedFollowUps(entityRepo,
      projects: projects, suppliers: suppliers);

  // Archive a slice of older projects so the close-recognition path
  // is exercised in reports.
  final archived = projects.take(kProjectCount ~/ 3).toList();
  for (final proj in archived) {
    final ageDays = kHistoryDays - 30 - _rng.nextInt(60);
    final archivedAt = DateTime.now()
        .toUtc()
        .subtract(Duration(days: ageDays))
        .toIso8601String();
    await db.update(
      'projects',
      {
        'is_archived': 1,
        'archived_at': archivedAt,
        'status': ProjectStatus.closed.db,
      },
      where: 'id = ?',
      whereArgs: [proj.project.id],
    );
  }
  stdout.writeln('  archived ${archived.length} projects');

  final journalCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM journal_entries')).first['c'] as int;
  final invCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM material_inventory')).first['c'] as int;
  final noteCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM notes')).first['c'] as int;
  final fuCount = (await db.rawQuery(
      'SELECT COUNT(*) AS c FROM follow_ups')).first['c'] as int;

  await db.close();

  final sizeKb = (outFile.lengthSync() / 1024).toStringAsFixed(1);
  stdout.writeln('');
  stdout.writeln('=== Done ===');
  stdout.writeln('  journal_entries:    $journalCount rows');
  stdout.writeln('  material_inventory: $invCount rows');
  stdout.writeln('  notes:              $noteCount rows');
  stdout.writeln('  follow_ups:         $fuCount rows');
  stdout.writeln('  file size:          $sizeKb KiB');
  stdout.writeln('');
  stdout.writeln('Import on device via Settings → Backup & Export → Import backup');
  stdout.writeln('  source path: $outPath');
}

// ────────────────────────────────────────────────────────────────────
//  Catalogs
// ────────────────────────────────────────────────────────────────────

const _kMaterialNames = <(String, MaterialUnit, UomType, double)>[
  ('Cement', MaterialUnit.bag, UomType.discrete, 1450),
  ('Sand', MaterialUnit.lump, UomType.volume, 3200),
  ('Crushed Aggregate', MaterialUnit.lump, UomType.volume, 4100),
  ('Brick - Red', MaterialUnit.pcs, UomType.discrete, 18),
  ('Brick - Fly Ash', MaterialUnit.pcs, UomType.discrete, 14),
  ('Steel Rebar 8mm', MaterialUnit.kg, UomType.weight, 285),
  ('Steel Rebar 10mm', MaterialUnit.kg, UomType.weight, 280),
  ('Steel Rebar 12mm', MaterialUnit.kg, UomType.weight, 278),
  ('Steel Rebar 16mm', MaterialUnit.kg, UomType.weight, 275),
  ('Wire Binding', MaterialUnit.kg, UomType.weight, 410),
  ('Tile - Floor', MaterialUnit.piece, UomType.discrete, 320),
  ('Tile - Wall', MaterialUnit.piece, UomType.discrete, 240),
  ('Paint - Emulsion', MaterialUnit.lump, UomType.volume, 1400),
  ('Paint - Enamel', MaterialUnit.lump, UomType.volume, 1850),
  ('PVC Pipe 1 inch', MaterialUnit.piece, UomType.discrete, 480),
  ('PVC Pipe 2 inch', MaterialUnit.piece, UomType.discrete, 720),
  ('Electrical Wire 1mm', MaterialUnit.lump, UomType.volume, 95),
  ('Electrical Wire 2.5mm', MaterialUnit.lump, UomType.volume, 165),
  ('Marble Slab', MaterialUnit.piece, UomType.discrete, 4800),
  ('Wood - Pine plank', MaterialUnit.piece, UomType.discrete, 1200),
  ('Glass Sheet', MaterialUnit.piece, UomType.discrete, 950),
  ('Door Frame', MaterialUnit.piece, UomType.discrete, 7500),
  ('Window Frame', MaterialUnit.piece, UomType.discrete, 5200),
];

const _kLabourNames = <(String, double)>[
  ('Mason', 1800),
  ('Mason Helper', 1100),
  ('Carpenter', 2200),
  ('Electrician', 2400),
  ('Plumber', 2300),
  ('Painter', 1700),
  ('Welder', 2100),
  ('Tile-fitter', 2000),
  ('Steel Fixer', 2500),
  ('Supervisor', 3500),
  ('Site labourer', 900),
  ('Driver', 1500),
];

Future<List<MaterialTypeDef>> _seedMaterialTypes(EntityRepository r) async {
  final out = <MaterialTypeDef>[];
  final pool = _kMaterialNames.take(kMaterialTypeCount).toList();
  for (final (name, unit, uomType, _) in pool) {
    final t = await r.addMaterialType(
      name,
      uomType: uomType,
      uom: unit.db,
    );
    if (t != null) out.add(t);
  }
  return out;
}

Future<List<LabourTypeDef>> _seedLabourTypes(EntityRepository r) async {
  final out = <LabourTypeDef>[];
  final pool = _kLabourNames.take(kLabourTypeCount).toList();
  for (final (name, rate) in pool) {
    final t = await r.addLabourType(name, defaultDailyRate: rate);
    if (t != null) out.add(t);
  }
  return out;
}

// ────────────────────────────────────────────────────────────────────
//  Entities
// ────────────────────────────────────────────────────────────────────

const _kBankNames = <(String, String)>[
  ('HBL Current', 'HBL-2347-99812'),
  ('Meezan Savings', 'MZN-9974-3320'),
  ('UBL Business', 'UBL-1133-77621'),
  ('Easypaisa Wallet', 'EP-0312-4488221'),
  ('Site Cash Safe', 'INTERNAL-SAFE-01'),
];

Future<List<Bank>> _seedBanks(EntityRepository r) async {
  final out = <Bank>[];
  for (var i = 0; i < kBankCount && i < _kBankNames.length; i++) {
    final (name, acct) = _kBankNames[i];
    out.add(await r.createBank(name: name, accountNo: acct));
  }
  return out;
}

const _kSupplierFirstParts = <String>[
  'Al-Madina', 'New Star', 'Royal', 'Saigon', 'Karachi', 'Punjab',
  'Sialkot', 'Lahore', 'Faisal', 'Mehran', 'United', 'Imperial',
  'Crown', 'Hilal', 'Sahara', 'Indus', 'Ravi', 'Margalla', 'Khaadi',
  'Sapphire', 'Bismillah', 'Tariq', 'Khan', 'Iqbal', 'Sufi', 'Diamond',
  'Pak', 'Sona', 'Chand', 'Sitara', 'Mughal', 'Salem', 'Hassan',
  'Awami', 'Express', 'Reliable', 'Quality', 'Premier', 'Capital',
  'Empire',
];
const _kSupplierLastParts = <String>[
  'Traders', 'Suppliers', 'Hardware', 'Construction',
  'Materials', 'Cement Depot', 'Steel House', 'Electricals',
  'Sanitary', 'Tiles', 'Paints', 'Builders', 'Enterprises',
  'Corporation', 'Brothers', 'Sons', 'Trading Co',
];

Future<List<Party>> _seedSuppliers(EntityRepository r) async {
  final out = <Party>[];
  for (var i = 0; i < kSupplierCount; i++) {
    final first = _kSupplierFirstParts[i % _kSupplierFirstParts.length];
    final last = _kSupplierLastParts[i % _kSupplierLastParts.length];
    final name = '$first $last';
    final phone = '03${10 + _rng.nextInt(90)}-${_rng.nextInt(10000000).toString().padLeft(7, '0')}';
    final cat = _rng.nextBool()
        ? SupplierCategory.material
        : SupplierCategory.labor;
    out.add(await r.createSupplier(
      name: name,
      phone: phone,
      category: cat,
    ));
  }
  return out;
}

const _kProjectAdjectives = <String>[
  'Bahria', 'DHA', 'Gulberg', 'Cantt', 'Model Town', 'Johar Town',
  'Wapda Town', 'Iqbal Town', 'Garden Town', 'Faisal Town',
  'Township', 'Valencia', 'Lake City', 'EME', 'Askari', 'Phase 5',
];
const _kProjectTypes = <String>[
  'House Construction', 'Boundary Wall', 'Renovation', '2nd Floor Extension',
  'Bathroom Remodel', 'Kitchen Upgrade', 'Garage Build', 'Roof Re-do',
  'Driveway Pavement', 'Front Façade', 'Servants Quarter',
];

Future<List<_ProjectRow>> _seedProjects(EntityRepository r) async {
  final out = <_ProjectRow>[];
  for (var i = 0; i < kProjectCount; i++) {
    final adj = _kProjectAdjectives[i % _kProjectAdjectives.length];
    final typ = _kProjectTypes[i % _kProjectTypes.length];
    final isWm = i % 3 != 0;
    final budget = isWm
        ? (1_500_000 + _rng.nextInt(8_500_000)).toDouble()
        : (500_000 + _rng.nextInt(3_000_000)).toDouble();
    final p = await r.createProject(
      name: '$adj — $typ',
      model: isWm ? ProjectModel.withMaterial : ProjectModel.labourRate,
      clientName: 'Client ${i + 1}',
      siteAddress: '${_rng.nextInt(900) + 1} Street ${_rng.nextInt(40) + 1}, $adj',
      budget: budget,
      projectManager: i.isEven ? 'Imran' : 'Tariq',
      serviceFeePercent: isWm ? null : (8 + _rng.nextInt(8)).toDouble(),
    );
    out.add(_ProjectRow(p, isWm, budget));
  }
  return out;
}

class _ProjectRow {
  _ProjectRow(this.project, this.isWm, this.budget);
  final Project project;
  final bool isWm;
  final double budget;
}

// ────────────────────────────────────────────────────────────────────
//  Transactions
// ────────────────────────────────────────────────────────────────────

Future<void> _seedTransactions({
  required Database db,
  required EntityRepository entityRepo,
  required LedgerRepository ledgerRepo,
  required List<_ProjectRow> projects,
  required List<Party> suppliers,
  required List<Bank> banks,
  required List<MaterialTypeDef> materialTypes,
}) async {
  for (var i = 0; i < kTransactionCount; i++) {
    final proj = projects[_rng.nextInt(projects.length)];
    final supplier = suppliers[_rng.nextInt(suppliers.length)];
    final bank = banks[_rng.nextInt(banks.length)];
    final bankAcct = Account(bank.id, bank.name, AccountType.asset);

    final kind = _pickTxnKind(proj.isWm);

    switch (kind) {
      case _Kind.materialBuy:
        final amount = (5_000 + _rng.nextInt(120_000)).toDouble();
        final txnId = await ledgerRepo.postMaterialBuy(
          amount: amount,
          projectId: proj.project.id,
          supplierId: supplier.id,
          description: 'Material delivery',
        );
        final mat = materialTypes[_rng.nextInt(materialTypes.length)];
        final unitPrice = _unitPriceFor(mat.name);
        final qty =
            (amount / unitPrice).clamp(1, 1000).toDouble().roundToDouble();
        await entityRepo.logMaterialPurchase(
          projectId: proj.project.id,
          supplierId: supplier.id,
          transactionId: txnId,
          materialType: mat.name,
          price: amount,
          quantity: qty,
          unit: mat.uom != null ? MaterialUnitX.fromDb(mat.uom!) : null,
        );

      case _Kind.materialCounter:
        final amount = (1_500 + _rng.nextInt(35_000)).toDouble();
        final txnId = await ledgerRepo.postMaterialCounter(
          amount: amount,
          projectId: proj.project.id,
          paidFrom: bankAcct,
          description: 'Counter purchase',
        );
        final mat = materialTypes[_rng.nextInt(materialTypes.length)];
        final unitPrice = _unitPriceFor(mat.name);
        final qty =
            (amount / unitPrice).clamp(1, 1000).toDouble().roundToDouble();
        await entityRepo.logMaterialPurchase(
          projectId: proj.project.id,
          transactionId: txnId,
          materialType: mat.name,
          price: amount,
          quantity: qty,
          unit: mat.uom != null ? MaterialUnitX.fromDb(mat.uom!) : null,
        );

      case _Kind.labourCredit:
        final amount = (3_000 + _rng.nextInt(40_000)).toDouble();
        await ledgerRepo.postLabourCredit(
          amount: amount,
          projectId: proj.project.id,
          supplierId: supplier.id,
          description: 'Wages on credit',
        );

      case _Kind.labourPayment:
        final amount = (3_000 + _rng.nextInt(40_000)).toDouble();
        await ledgerRepo.postLabourPayment(
          amount: amount,
          projectId: proj.project.id,
          supplierId: supplier.id,
          paidFrom: bankAcct,
          description: 'Wage payment',
        );

      case _Kind.supplierPay:
        // Skip if the supplier doesn't actually owe anything — avoids
        // posting bogus overpayments for every random supplier.
        final owed = await ledgerRepo.supplierPayableBalance(supplier.id);
        if (owed < 100) continue;
        final amount = (owed * (0.3 + _rng.nextDouble() * 0.7))
            .clamp(100.0, owed)
            .toDouble();
        await ledgerRepo.postSupplierPay(
          amount: amount,
          supplierId: supplier.id,
          paidFrom: bankAcct,
          projectId: proj.project.id,
          description: 'Settlement',
        );

      case _Kind.receive:
        final amount = (proj.budget * (0.05 + _rng.nextDouble() * 0.25))
            .clamp(10_000.0, proj.budget)
            .toDouble();
        await ledgerRepo.postReceiveFromProject(
          amount: amount,
          projectId: proj.project.id,
          receivedInto: bankAcct,
          description: 'Customer payment',
        );

      case _Kind.serviceFee:
        if (!proj.isWm) {
          final amount = (5_000 + _rng.nextInt(60_000)).toDouble();
          await ledgerRepo.postServiceFee(
            amount: amount,
            projectId: proj.project.id,
            receivedInto: bankAcct,
            description: 'Service fee earned',
          );
        }

      case _Kind.transfer:
        final from = bankAcct;
        Account to;
        do {
          final b2 = banks[_rng.nextInt(banks.length)];
          to = Account(b2.id, b2.name, AccountType.asset);
        } while (to.id == from.id);
        final amount = (5_000 + _rng.nextInt(150_000)).toDouble();
        await ledgerRepo.postWalletTransfer(
          amount: amount,
          from: from,
          to: to,
          description: 'Wallet transfer',
        );

      case _Kind.personalDraw:
        final amount = (5_000 + _rng.nextInt(80_000)).toDouble();
        await ledgerRepo.postPersonalDraw(
          amount: amount,
          paidFrom: bankAcct,
          description: 'Owner draw',
        );
    }

    if (i % 200 == 199) {
      stdout.writeln('  transactions: ${i + 1}/$kTransactionCount');
    }
  }

  // Backdate every transaction's created_at uniformly across the
  // history window so reports show a 12-month spread instead of a
  // single "right now" spike. Both legs of a posting share the same
  // timestamp via transaction_id.
  stdout.writeln('  backdating timestamps across $kHistoryDays days...');
  final txnIds = await db.rawQuery(
      'SELECT DISTINCT transaction_id FROM journal_entries');
  final nowUtc = DateTime.now().toUtc();
  for (final row in txnIds) {
    final id = row['transaction_id'] as String;
    final ageDays = _rng.nextInt(kHistoryDays);
    final ageHours = _rng.nextInt(24);
    final iso = nowUtc
        .subtract(Duration(days: ageDays, hours: ageHours))
        .toIso8601String();
    await db.update('journal_entries', {'created_at': iso},
        where: 'transaction_id = ?', whereArgs: [id]);
    await db.update('material_inventory', {'created_at': iso},
        where: 'transaction_id = ?', whereArgs: [id]);
  }
}

// Weighted random transaction-kind picker. Skews toward material
// buys / labour activity since those dominate a real ledger.
_Kind _pickTxnKind(bool projectIsWm) {
  final r = _rng.nextDouble();
  if (r < 0.30) return _Kind.materialBuy;
  if (r < 0.42) return _Kind.materialCounter;
  if (r < 0.55) return _Kind.labourCredit;
  if (r < 0.70) return _Kind.labourPayment;
  if (r < 0.78) return _Kind.supplierPay;
  if (r < 0.90) return _Kind.receive;
  if (r < 0.93) return projectIsWm ? _Kind.materialBuy : _Kind.serviceFee;
  if (r < 0.97) return _Kind.transfer;
  return _Kind.personalDraw;
}

enum _Kind {
  materialBuy,
  materialCounter,
  labourCredit,
  labourPayment,
  supplierPay,
  receive,
  serviceFee,
  transfer,
  personalDraw,
}

double _unitPriceFor(String name) {
  for (final (n, _, _, price) in _kMaterialNames) {
    if (n == name) return price;
  }
  return 100;
}

// ────────────────────────────────────────────────────────────────────
//  Notes
// ────────────────────────────────────────────────────────────────────

const _kNoteSnippets = <String>[
  'Customer wants polished concrete on the porch — confirm before the slab pour.',
  'Sand pile is on the south side; mixer goes north of the trench.',
  'Supplier promised next-day delivery but came 3 days late twice this month.',
  'Pay before Friday or 2% late fee per the verbal agreement.',
  'Owner asked to switch from emulsion to plastic emulsion paint.',
  'Marble samples shortlisted — see WhatsApp photos from 14th.',
  'Electrician is on vacation till the 22nd; reassign panel wiring.',
  'Site access via back gate during school hours.',
  'Steel rates dropped 5% — restock before they bounce back.',
  'Plumber under-charged by Rs 2500 last visit; adjust in next payment.',
  'Boundary wall needs 4 extra rows of brick per the new plan.',
  'Kitchen counter granite is from a different lot — colour match risky.',
  'Window frames need anti-rust primer before installation.',
  'Owner is travelling till next month; deputy is the point of contact.',
  'Cement bag count was 2 short on the last delivery — escalate.',
];

Future<void> _seedNotes(
  EntityRepository r, {
  required List<_ProjectRow> projects,
  required List<Party> suppliers,
}) async {
  for (var i = 0; i < kNoteCount; i++) {
    final onProject = i % 3 != 0;
    if (onProject) {
      await r.addNote(
        type: NoteEntityType.project,
        entityId: projects[_rng.nextInt(projects.length)].project.id,
        body: _kNoteSnippets[_rng.nextInt(_kNoteSnippets.length)],
        pinned: _rng.nextDouble() < 0.15,
      );
    } else {
      await r.addNote(
        type: NoteEntityType.supplier,
        entityId: suppliers[_rng.nextInt(suppliers.length)].id,
        body: _kNoteSnippets[_rng.nextInt(_kNoteSnippets.length)],
        pinned: _rng.nextDouble() < 0.15,
      );
    }
  }
}

// ────────────────────────────────────────────────────────────────────
//  Follow-Ups
// ────────────────────────────────────────────────────────────────────

const _kFollowUpTitles = <String>[
  'Collect Rs 2L pending payment',
  'Send reminder for invoice 0042',
  'Confirm delivery date with supplier',
  'Chase signed BOQ before mobilisation',
  'Recover overpayment from cement vendor',
  'Submit revised quote to client',
  'Pick up material samples from depot',
  'Pay electrician (2 weeks pending)',
  'Get bank statement for last quarter',
  'Re-quote tile package — owner requested',
  'Resolve dispute over short delivery',
  'Renew supervisor monthly cash float',
];

Future<void> _seedFollowUps(
  EntityRepository r, {
  required List<_ProjectRow> projects,
  required List<Party> suppliers,
}) async {
  final now = DateTime.now();
  for (var i = 0; i < kFollowUpCount; i++) {
    DateTime? expected;
    final t = _rng.nextDouble();
    if (t < 0.4) {
      expected = now.subtract(Duration(days: 1 + _rng.nextInt(20)));
    } else if (t < 0.85) {
      expected = now.add(Duration(days: _rng.nextInt(30)));
    } else {
      expected = null;
    }
    final priority = switch (_rng.nextInt(3)) {
      0 => FollowUpPriority.high,
      1 => FollowUpPriority.medium,
      _ => FollowUpPriority.low,
    };
    final hasProject = _rng.nextDouble() < 0.7;
    final f = await r.addFollowUp(
      title: _kFollowUpTitles[_rng.nextInt(_kFollowUpTitles.length)],
      note: _rng.nextBool() ? 'See last conversation in WhatsApp.' : null,
      projectId: hasProject
          ? projects[_rng.nextInt(projects.length)].project.id
          : null,
      supplierId: hasProject
          ? null
          : suppliers[_rng.nextInt(suppliers.length)].id,
      expectedDate: expected,
      priority: priority,
      amountEstimate: _rng.nextDouble() < 0.6
          ? (5_000 + _rng.nextInt(200_000)).toDouble()
          : null,
    );

    // Mark some as resolved so the resolved view has data.
    if (_rng.nextDouble() < 0.25) {
      await r.resolveFollowUp(f.id);
    }
  }
}
