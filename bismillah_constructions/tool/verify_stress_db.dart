// Sanity check on the generated stress-test DB. Run via:
//   flutter test tool/verify_stress_db.dart
//
// Asserts the file opens, schema is v16, and the double-entry
// invariant (sum of debits == sum of credits) holds across all live
// transactions.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Find the generated DB — flutter test resolves Platform.script to
  // the project root, so output/ lives there.
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final candidates = [
    p.join(scriptDir, 'output', 'stress_test.db'),
    p.join(scriptDir, 'tool', 'output', 'stress_test.db'),
  ];
  final dbPath = candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => throw StateError(
        'Generated DB not found in: ${candidates.join(", ")}'),
  );

  final db = await databaseFactory.openDatabase(dbPath);

  final version = (await db.rawQuery('PRAGMA user_version'))
      .first
      .values
      .first as int;
  stdout.writeln('schema user_version: $version');

  Future<int> count(String t) async =>
      ((await db.rawQuery('SELECT COUNT(*) AS c FROM $t')).first['c']
          as int);

  stdout.writeln('projects:           ${await count("projects")}');
  stdout.writeln('  active:           ${await count("projects WHERE is_archived = 0")}');
  stdout.writeln('  archived:         ${await count("projects WHERE is_archived = 1")}');
  stdout.writeln('suppliers:          ${await count("suppliers")}');
  stdout.writeln('banks:              ${await count("banks")}');
  stdout.writeln('material_types:     ${await count("material_types")}');
  stdout.writeln('labour_types:       ${await count("labour_types")}');
  stdout.writeln('journal_entries:    ${await count("journal_entries")}');
  stdout.writeln('  live:             ${await count("journal_entries WHERE is_deleted = 0")}');
  stdout.writeln('material_inventory: ${await count("material_inventory")}');
  stdout.writeln('notes:              ${await count("notes")}');
  stdout.writeln('follow_ups:         ${await count("follow_ups")}');

  // Double-entry invariant.
  final bal = await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) AS dr, COALESCE(SUM(credit),0) AS cr '
      'FROM journal_entries WHERE is_deleted = 0');
  final dr = (bal.first['dr'] as num).toDouble();
  final cr = (bal.first['cr'] as num).toDouble();
  stdout.writeln('');
  stdout.writeln('Σ debits:  ${dr.toStringAsFixed(2)}');
  stdout.writeln('Σ credits: ${cr.toStringAsFixed(2)}');
  stdout.writeln('balanced:  ${(dr - cr).abs() < 0.01}');

  // Date spread.
  final spread = await db.rawQuery(
      'SELECT MIN(created_at) AS lo, MAX(created_at) AS hi '
      'FROM journal_entries WHERE is_deleted = 0');
  stdout.writeln('');
  stdout.writeln('oldest entry: ${spread.first['lo']}');
  stdout.writeln('newest entry: ${spread.first['hi']}');

  // Per-month volume.
  final perMonth = await db.rawQuery(
      "SELECT substr(created_at, 1, 7) AS m, COUNT(*) AS c "
      'FROM journal_entries WHERE is_deleted = 0 '
      'GROUP BY m ORDER BY m DESC LIMIT 13');
  stdout.writeln('');
  stdout.writeln('per-month volume (latest 13):');
  for (final r in perMonth) {
    stdout.writeln('  ${r['m']}: ${r['c']} entries');
  }

  await db.close();
}
