import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  String? _dbPath;

  /// Absolute path of the open database — used by backup service.
  String? get dbPath => _dbPath;

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
        version: 3,
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
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE banks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        account_no TEXT,
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
        customer_id TEXT,
        site_address TEXT,
        budget REAL,
        project_manager TEXT,
        service_fee_percent REAL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
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
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

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
