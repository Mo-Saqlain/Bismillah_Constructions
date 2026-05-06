/// Account IDs and types — the Chart of Accounts.
library;

enum AccountType { asset, liability, income, expense, equity }

class Account {
  final String id;
  final String name;
  final AccountType type;
  const Account(this.id, this.name, this.type);
}

/// System (built-in) accounts. Banks / wallets defined by the user are loaded
/// at runtime from the `banks` table and joined onto these for the cash-like
/// list — see [cashLikeAccountsProvider].
class Accounts {
  // Assets — system
  static const cash = Account('CASH', 'Cash', AccountType.asset);
  static const supervisorFloat =
      Account('SUPERVISOR_FLOAT', 'Supervisor Float', AccountType.asset);
  static const externalWallet =
      Account('EXTERNAL_WALLET', 'External Wallet', AccountType.asset);

  // Liabilities
  static const supplierPayables =
      Account('SUPPLIER_PAY', 'Supplier Payables', AccountType.liability);

  // Income
  static const projectRevenue =
      Account('PROJECT_REV', 'Project Revenue', AccountType.income);
  static const serviceFeeIncome =
      Account('SERVICE_FEE', 'Service Fee Income', AccountType.income);

  // Expenses
  static const materialCosts =
      Account('MATERIAL_COSTS', 'Material Costs', AccountType.expense);
  static const labourCosts =
      Account('LABOUR_COSTS', 'Labour Costs', AccountType.expense);
  static const personalDraw =
      Account('PERSONAL_DRAW', 'Personal / Daily Draw', AccountType.expense);

  // Equity
  static const ownersEquity =
      Account('OWNERS_EQUITY', "Owner's Equity", AccountType.equity);

  /// All built-in accounts (does not include user-defined banks).
  static const all = <Account>[
    cash,
    supervisorFloat,
    externalWallet,
    supplierPayables,
    projectRevenue,
    serviceFeeIncome,
    materialCosts,
    labourCosts,
    personalDraw,
    ownersEquity,
  ];

  static Account byId(String id) =>
      all.firstWhere((a) => a.id == id,
          orElse: () => Account(id, id, AccountType.asset));

  /// System cash-like wallets ALWAYS available (Cash + Supervisor Float).
  /// User-defined banks are appended at runtime via `cashLikeAccountsProvider`.
  static const systemCashLike = <Account>[cash, supervisorFloat];
}

enum ProjectModel { withMaterial, labourRate }

extension ProjectModelX on ProjectModel {
  String get label => switch (this) {
        ProjectModel.withMaterial => 'With Material',
        ProjectModel.labourRate => 'Labour Rate',
      };
  String get db => name;
  static ProjectModel fromDb(String s) =>
      ProjectModel.values.firstWhere((v) => v.name == s,
          orElse: () => ProjectModel.withMaterial);
}

enum ProjectStatus { active, closed }

extension ProjectStatusX on ProjectStatus {
  String get label => switch (this) {
        ProjectStatus.active => 'Active',
        ProjectStatus.closed => 'Closed',
      };
  String get db => name;
  static ProjectStatus fromDb(String s) =>
      ProjectStatus.values.firstWhere((v) => v.name == s,
          orElse: () => ProjectStatus.active);
}

enum SupplierCategory { labor, material }

extension SupplierCategoryX on SupplierCategory {
  String get label => switch (this) {
        SupplierCategory.labor => 'Labor',
        SupplierCategory.material => 'Material',
      };
  String get db => name;
  static SupplierCategory fromDb(String s) =>
      SupplierCategory.values.firstWhere((v) => v.name == s,
          orElse: () => SupplierCategory.material);
}

enum CounterEntityType { receivable, payable }

extension CounterEntityTypeX on CounterEntityType {
  String get label => switch (this) {
        CounterEntityType.receivable => 'Receivable (Asset)',
        CounterEntityType.payable => 'Payable (Liability)',
      };
  String get db => name;
  static CounterEntityType fromDb(String s) =>
      CounterEntityType.values.firstWhere((v) => v.name == s,
          orElse: () => CounterEntityType.receivable);
}

enum MaterialType { brick, cement, sarya, finishing, other }

extension MaterialTypeX on MaterialType {
  String get label => switch (this) {
        MaterialType.brick => 'Brick',
        MaterialType.cement => 'Cement',
        MaterialType.sarya => 'Sarya (Steel)',
        MaterialType.finishing => 'Finishing',
        MaterialType.other => 'Other',
      };
  String get db => name;

  static MaterialType fromDb(String s) =>
      MaterialType.values.firstWhere((v) => v.name == s,
          orElse: () => MaterialType.cement);
}

/// Legacy unit retained for schema compatibility. New entries record `lump`
/// because the UI only collects a price (quantity goes in the memo).
enum MaterialUnit { lump, pcs, bag, kg, piece }

extension MaterialUnitX on MaterialUnit {
  String get label => switch (this) {
        MaterialUnit.lump => 'Lump-sum',
        MaterialUnit.pcs => 'Pcs (count)',
        MaterialUnit.bag => 'Bag',
        MaterialUnit.kg => 'KG',
        MaterialUnit.piece => 'Piece',
      };
  String get db => name;
  static MaterialUnit fromDb(String s) =>
      MaterialUnit.values.firstWhere((v) => v.name == s,
          orElse: () => MaterialUnit.lump);
}

enum MaterialTxnType { purchase, consumption }

extension MaterialTxnTypeX on MaterialTxnType {
  String get db => name;
  static MaterialTxnType fromDb(String s) =>
      MaterialTxnType.values.firstWhere((v) => v.name == s,
          orElse: () => MaterialTxnType.purchase);
}

/// Canonical transaction types — money flows in or out of a project.
enum TxnKind {
  materialBuy,         // Dr Material Costs / Cr Supplier Payables (project mandatory)
  labourPayment,       // Dr Labour Costs / Cr Cash|Bank  (project mandatory)
  supplierPay,         // Dr Supplier Payables / Cr Cash|Bank
  receiveFromProject,  // Dr Cash|Bank / Cr Project Revenue (direct receipt — no receivable phase)
  walletTransfer,      // Dr destination wallet / Cr source wallet
  personalDraw,        // Dr Personal Draw / Cr Cash|Bank (does NOT touch payables)
  serviceFee,          // Dr Cash|Bank / Cr Service Fee Income (labour-rate model)
}

extension TxnKindX on TxnKind {
  String get label => switch (this) {
        TxnKind.materialBuy => 'Material Buy (Credit)',
        TxnKind.labourPayment => 'Labour Payment',
        TxnKind.supplierPay => 'Material Payment',
        TxnKind.receiveFromProject => 'Receive from Project',
        TxnKind.walletTransfer => 'Wallet Transfer',
        TxnKind.personalDraw => 'Personal / Daily Draw',
        TxnKind.serviceFee => 'Service Fee Logged',
      };
  String get blurb => switch (this) {
        TxnKind.materialBuy =>
          'Buy material on credit from a supplier (project required)',
        TxnKind.labourPayment =>
          'Pay a labour provider for a project (project required)',
        TxnKind.supplierPay =>
          'Settle a payable to a material supplier from cash or bank',
        TxnKind.receiveFromProject =>
          'Receive money from the project — booked as project revenue',
        TxnKind.walletTransfer =>
          'Move cash between bank / cash / supervisor wallets',
        TxnKind.personalDraw =>
          'Daily / personal expense — keeps payables intact',
        TxnKind.serviceFee =>
          'Log service fee earned (% of project spend, labour-rate model)',
      };
}

/// Action recorded in the change log.
enum ChangeAction { delete, restore, archive, unarchive, edit }

extension ChangeActionX on ChangeAction {
  String get label => switch (this) {
        ChangeAction.delete => 'Deleted',
        ChangeAction.restore => 'Restored',
        ChangeAction.archive => 'Archived',
        ChangeAction.unarchive => 'Unarchived',
        ChangeAction.edit => 'Edited',
      };
  String get db => name;
  static ChangeAction fromDb(String s) =>
      ChangeAction.values.firstWhere((v) => v.name == s,
          orElse: () => ChangeAction.edit);
}

/// App-wide settings keys (stored in `app_settings` table).
class SettingsKeys {
  static const themeMode = 'theme_mode'; // 'light' | 'dark' | 'system'
  static const lastBackupAt = 'last_backup_at';
  static const deviceId = 'device_id';
}

class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
}
