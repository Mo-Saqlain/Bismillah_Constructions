import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  /// Test-only: applies the latest schema to an open db. Real callers go
  /// through [open], which routes through [_onCreate] / [_onUpgrade] like
  /// normal.
  @visibleForTesting
  Future<void> applySchemaForTests(Database db) => _onCreate(db, 10);

  Database? _db;
  String? _dbPath;

  /// Absolute path of the open database — used by backup service.
  String? get dbPath => _dbPath;

  /// Closes the database connection so that [open] can reopen it with new
  /// content — called by the auto-restore flow after copying a backup file
  /// to [dbPath].
  Future<void> reinitialize() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> open() async {
    if (_db != null) return _db!;

    DatabaseFactory factory;
    String path;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
      final dir = await getApplicationSupportDirectory();
      path = p.join(dir.path, 'solo_con.db');
    } else {
      factory = databaseFactory;
      path = p.join(await getDatabasesPath(), 'solo_con.db');
    }
    _dbPath = path;

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        ntn_cnic TEXT,
        address TEXT,
        credit_limit REAL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        category TEXT,
        tax_status TEXT,
        bank_details TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE banks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        account_no TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE counter_entities (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        model TEXT NOT NULL,
        status TEXT NOT NULL,
        customer_id TEXT,                      -- legacy, kept for migration
        client_name TEXT,                      -- v5: free-text client (replaces customer fk)
        site_address TEXT,
        budget REAL,
        project_manager TEXT,
        service_fee_percent REAL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE material_inventory (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        transaction_id TEXT,
        material_type TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        rate REAL NOT NULL,
        total_cost REAL NOT NULL,
        txn_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE journal_entries (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        project_id TEXT,
        supplier_id TEXT,
        customer_id TEXT,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        description TEXT,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE change_log (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        original_data TEXT,
        new_data TEXT,
        note TEXT,
        device_id TEXT,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // v7 base columns + v8 procurement metadata. uom_typ is one of
    // 'discrete' / 'surface' / 'volume' / 'weight'; cov_rate / dims are
    // only meaningful for some uom_typ values, so they're nullable.
    //
    // is_builtin used to lock the original five seeded rows from deletion.
    // v9 removed seeding entirely (the user wants to define every material
    // type themselves), so the column is left for backwards-compat with
    // upgraded installs but is no longer enforced anywhere.
    await db.execute('''
      CREATE TABLE material_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        uom_typ TEXT,
        uom TEXT,
        cov_rate REAL,
        waste_f REAL,
        lead_d INTEGER,
        dims TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    // No seeds. Fresh installs start with an empty material catalog so the
    // user can define every type from scratch.

    await db.execute(
      'CREATE INDEX idx_je_txn ON journal_entries(transaction_id)',
    );
    await db.execute(
      'CREATE INDEX idx_je_account ON journal_entries(account_id)',
    );
    await db.execute(
      'CREATE INDEX idx_je_project ON journal_entries(project_id)',
    );
    await db.execute(
      'CREATE INDEX idx_je_supplier ON journal_entries(supplier_id)',
    );
    await db.execute(
      'CREATE INDEX idx_je_customer ON journal_entries(customer_id)',
    );
    await db.execute('CREATE INDEX idx_je_synced ON journal_entries(synced)');
    await db.execute(
      'CREATE INDEX idx_je_deleted ON journal_entries(is_deleted)',
    );
    await db.execute(
      'CREATE INDEX idx_cl_entity ON change_log(entity_type, entity_id)',
    );

    await db.execute('''
      CREATE TABLE labour_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        default_daily_rate REAL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE customers ADD COLUMN ntn_cnic TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN credit_limit REAL');
      await db.execute('ALTER TABLE suppliers ADD COLUMN category TEXT');
      await db.execute('ALTER TABLE suppliers ADD COLUMN tax_status TEXT');
      await db.execute('ALTER TABLE suppliers ADD COLUMN bank_details TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN customer_id TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN site_address TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN budget REAL');
      await db.execute('ALTER TABLE projects ADD COLUMN project_manager TEXT');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS banks (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          account_no TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS counter_entities (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          amount REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS material_inventory (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL,
          supplier_id TEXT NOT NULL,
          transaction_id TEXT,
          material_type TEXT NOT NULL,
          unit TEXT NOT NULL,
          quantity REAL NOT NULL,
          rate REAL NOT NULL,
          total_cost REAL NOT NULL,
          txn_type TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 4) {
      // v4: device_id on change_log so audits identify the writing install.
      try {
        await db.execute('ALTER TABLE change_log ADD COLUMN device_id TEXT');
      } catch (_) {/* column may already exist on fresh installs */}
    }

    if (oldVersion < 6) {
      // v6: archival on suppliers + banks (parity with projects). Keeps the
      // ledger history intact while hiding the row from default lists.
      for (final table in const ['suppliers', 'banks']) {
        try {
          await db.execute(
              'ALTER TABLE $table ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0');
        } catch (_) {/* may already exist */}
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN archived_at TEXT');
        } catch (_) {/* may already exist */}
      }
    }

    if (oldVersion < 5) {
      // v5: free-text `client_name` on projects (replaces the customer FK
      // for the user's flow). Banks become user-defined accounts — seed the
      // legacy hardcoded bank ids into the `banks` table when they are
      // referenced by existing journal_entries so old data keeps a
      // human-readable label.
      try {
        await db.execute('ALTER TABLE projects ADD COLUMN client_name TEXT');
      } catch (_) {/* may already exist */}

      const seeds = <Map<String, String>>[
        {'id': 'BANK_HBL', 'name': 'Bank — HBL'},
        {'id': 'BANK_MEEZAN', 'name': 'Bank — Meezan'},
        {'id': 'BANK_ALFALAH', 'name': 'Bank — Alfalah'},
      ];
      for (final s in seeds) {
        final hits = await db.rawQuery(
          'SELECT 1 FROM journal_entries WHERE account_id = ? LIMIT 1',
          [s['id']],
        );
        if (hits.isNotEmpty) {
          await db.insert(
            'banks',
            {
              'id': s['id'],
              'name': s['name'],
              'account_no': null,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    }

    if (oldVersion < 7) {
      // v7: user-defined material types table. Originally the five legacy
      // enum values were seeded as built-ins; v9 removed that — so we
      // create the table empty and let the user define their own rows.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS material_types (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          is_builtin INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 8) {
      // v8: procurement metadata on material types. All nullable so existing
      // rows survive untouched; the UI offers them as optional fields.
      for (final ddl in const [
        'ALTER TABLE material_types ADD COLUMN uom_typ TEXT',
        'ALTER TABLE material_types ADD COLUMN uom TEXT',
        'ALTER TABLE material_types ADD COLUMN cov_rate REAL',
        'ALTER TABLE material_types ADD COLUMN waste_f REAL',
        'ALTER TABLE material_types ADD COLUMN lead_d INTEGER',
        'ALTER TABLE material_types ADD COLUMN dims TEXT',
      ]) {
        try {
          await db.execute(ddl);
        } catch (_) {/* may already exist on partial upgrades */}
      }
    }

    if (oldVersion < 9) {
      // v9: drop the seeded built-in material types — the user wants to
      // define every category themselves. Historical material_inventory
      // rows still display correctly because they store the type name as
      // a free-form string, not a foreign key.
      await db.delete('material_types', where: 'is_builtin = 1');
    }

    if (oldVersion < 10) {
      // v10: user-defined labour categories (Mason, Electrician, etc.).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS labour_types (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          description TEXT,
          default_daily_rate REAL,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 3) {
      // v3: soft delete, archive, change log, settings, service fee
      await db.execute(
          'ALTER TABLE journal_entries ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE journal_entries ADD COLUMN deleted_at TEXT');
      await db.execute(
          'ALTER TABLE projects ADD COLUMN service_fee_percent REAL');
      await db.execute(
          'ALTER TABLE projects ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE projects ADD COLUMN archived_at TEXT');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS change_log (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          action TEXT NOT NULL,
          original_data TEXT,
          new_data TEXT,
          note TEXT,
          timestamp TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_je_deleted ON journal_entries(is_deleted)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cl_entity ON change_log(entity_type, entity_id)');
    }
  }

}
