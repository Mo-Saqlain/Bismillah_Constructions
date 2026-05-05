/// Account IDs and types — the Chart of Accounts.
library;

enum AccountType { asset, liability, income, expense, equity }

class Account {
  final String id;
  final String name;
  final AccountType type;
  const Account(this.id, this.name, this.type);
}

class Accounts {
  // Assets
  static const cash = Account('CASH', 'Cash', AccountType.asset);
  static const bankHbl = Account('BANK_HBL', 'Bank — HBL', AccountType.asset);
  static const bankMeezan =
      Account('BANK_MEEZAN', 'Bank — Meezan', AccountType.asset);
  static const bankAlfalah =
      Account('BANK_ALFALAH', 'Bank — Alfalah', AccountType.asset);
  static const supervisorFloat =
      Account('SUPERVISOR_FLOAT', 'Supervisor Float', AccountType.asset);
  static const externalWallet =
      Account('EXTERNAL_WALLET', 'External Wallet', AccountType.asset);
  static const clientReceivables =
      Account('CLIENT_RECV', 'Client Receivables', AccountType.asset);
  static const counterReceivables =
      Account('COUNTER_RECV', 'Counter Receivables', AccountType.asset);

  // Liabilities
  static const supplierPayables =
      Account('SUPPLIER_PAY', 'Supplier Payables', AccountType.liability);
  static const counterPayables =
      Account('COUNTER_PAY', 'Counter Payables', AccountType.liability);

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

  static const all = <Account>[
    cash,
    bankHbl,
    bankMeezan,
    bankAlfalah,
    supervisorFloat,
    externalWallet,
    clientReceivables,
    counterReceivables,
    supplierPayables,
    counterPayables,
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

  /// Cash + Bank + Supervisor Float — accounts the user can pay/receive from.
  static const cashLikeAccounts = <Account>[
    cash,
    bankHbl,
    bankMeezan,
    bankAlfalah,
    supervisorFloat,
  ];

  /// Bank ledgers only — used for Liquid_Cash dashboard formula.
  static const bankAccounts = <Account>[
    bankHbl,
    bankMeezan,
    bankAlfalah,
  ];

  /// Supervisor float buckets — Cash and Supervisor Float per spec.
  static const supervisorFloatAccounts = <Account>[
    cash,
    supervisorFloat,
  ];
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

enum MaterialType { brick, cement, sarya, finishing }

extension MaterialTypeX on MaterialType {
  String get label => switch (this) {
        MaterialType.brick => 'Brick',
        MaterialType.cement => 'Cement',
        MaterialType.sarya => 'Sarya (Steel)',
        MaterialType.finishing => 'Finishing',
      };
  String get db => name;

  MaterialUnit get defaultUnit => switch (this) {
        MaterialType.brick => MaterialUnit.pcs,
        MaterialType.cement => MaterialUnit.bag,
        MaterialType.sarya => MaterialUnit.kg,
        MaterialType.finishing => MaterialUnit.piece,
      };

  static MaterialType fromDb(String s) =>
      MaterialType.values.firstWhere((v) => v.name == s,
          orElse: () => MaterialType.cement);
}

enum MaterialUnit { pcs, bag, kg, piece }

extension MaterialUnitX on MaterialUnit {
  String get label => switch (this) {
        MaterialUnit.pcs => 'Pcs (count)',
        MaterialUnit.bag => 'Bag',
        MaterialUnit.kg => 'KG',
        MaterialUnit.piece => 'Piece',
      };
  String get db => name;
  static MaterialUnit fromDb(String s) =>
      MaterialUnit.values.firstWhere((v) => v.name == s,
          orElse: () => MaterialUnit.pcs);
}

enum MaterialTxnType { purchase, consumption }

extension MaterialTxnTypeX on MaterialTxnType {
  String get db => name;
  static MaterialTxnType fromDb(String s) =>
      MaterialTxnType.values.firstWhere((v) => v.name == s,
          orElse: () => MaterialTxnType.purchase);
}

/// Canonical transaction types.
///
/// The original five from spec section 4 plus three new ones for v5.6:
/// inter-wallet transfer, personal/daily draw, and service fee.
enum TxnKind {
  materialBuy,     // Dr Material Costs / Cr Supplier Payables
  labourPayment,   // Dr Labour Costs / Cr Cash|Bank  (mandatory provider)
  supplierPay,     // Dr Supplier Payables / Cr Cash|Bank
  clientBilling,   // Dr Client Receivables / Cr Project Revenue
  receivePayment,  // Dr Cash|Bank / Cr Client Receivables
  walletTransfer,  // Dr destination wallet / Cr source wallet
  personalDraw,    // Dr Personal Draw / Cr Cash|Bank (does NOT touch payables)
  serviceFee,      // Dr Cash|Bank / Cr Service Fee Income (labour-rate model)
}

extension TxnKindX on TxnKind {
  String get label => switch (this) {
        TxnKind.materialBuy => 'Material Buy (Credit)',
        TxnKind.labourPayment => 'Labour Payment',
        TxnKind.supplierPay => 'Supplier Payment',
        TxnKind.clientBilling => 'Client Billing',
        TxnKind.receivePayment => 'Receive Payment',
        TxnKind.walletTransfer => 'Wallet Transfer',
        TxnKind.personalDraw => 'Personal / Daily Draw',
        TxnKind.serviceFee => 'Service Fee Logged',
      };
  String get blurb => switch (this) {
        TxnKind.materialBuy => 'Buy material on credit from a supplier',
        TxnKind.labourPayment =>
          'Pay a labour provider for a project (cash or bank)',
        TxnKind.supplierPay => 'Settle a supplier payable from cash or bank',
        TxnKind.clientBilling =>
          'Bill a customer for a project (creates receivable)',
        TxnKind.receivePayment =>
          'Receive payment from a customer into cash or bank',
        TxnKind.walletTransfer =>
          'Move cash between bank/cash/supervisor wallets',
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
}

class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
}
