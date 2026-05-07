# Bismillah Constructions ERP

> Offline-first, double-entry construction-project ledger built in Flutter.
> Designed for a single operator running multiple sites: cash, banks, suppliers, materials, labour, and project P&L — all in one place, backed up locally.

---

## 1. What the application does

Bismillah Constructions ERP is a desktop / mobile / Android-tablet app that records every rupee that moves through a small-to-mid construction business and turns it into reports the owner can use to make decisions.

It supports two contract models simultaneously:

| Model            | Revenue recognition                                            | Use when                                                               |
| ---------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **With-Material**| Revenue = money received (capped at budget). Surplus = customer deposit owed back. | The business buys materials and pays labour itself. |
| **Labour-Rate**  | Revenue = service fee only. Everything else is a customer pass-through. | The business earns a fixed % fee; the customer's money funds all spend. |

Every cash movement is recorded as a balanced **debit/credit pair** on a fixed Chart of Accounts, so the Income Statement, Balance Sheet, and Cash Flow come out correct by construction.

### Headline feature list

- **Transactions** — 10 canonical posting kinds. Each posts a guaranteed-balanced journal entry.
- **Reconciliation gate** — With-Material projects can only be archived when all supplier payables are cleared. Labour-Rate projects must have the service fee reclassified first.
- **Soft delete + reversal** — every delete is reversible; reversals post new offsetting transactions.
- **Audit log** — every edit / delete / archive records `{timestamp, action, oldData, newData, deviceId, note}`.
- **Local backup** — full `.db` file copy every 6 h on cold boot (or on demand). Survives app uninstall on Android (external Documents folder).
- **Reports** — Income Statement (LR/WM aware), Balance Sheet, Cash Flow, Aging (0-30 / 31-60 / 61-90 / 90+), Budget vs Actual, Wage Register, Project Profitability, Supplier Ledger, Bank Ledger, Material Supplier Ledger.
- **Charts** — Budget allocation pie, Material breakdown pie, Spending over time (day/week/month bar), Project profitability bar, Burn curve, Price trend, Cash position, Liquidity gauge.
- **Exports** — every statement exports to **CSV**; major ones to **PDF**.
- **Theme** — Light / Dark / System. Blue = positive, red = negative.
- **Flat permissions** — single-operator app; no roles, no PIN.
- **FBR-ready** — Labour type catalog, supplier tax-status and bank-details fields for regulatory reporting.

---

## 2. Tech stack

| Concern              | Choice                                              |
| -------------------- | --------------------------------------------------- |
| Language / runtime   | Dart 3.11.5, Flutter 3.x                            |
| State management     | `flutter_riverpod` 2.x                              |
| Local DB             | `sqflite` + `sqflite_common_ffi` (desktop)          |
| Charts               | `fl_chart` 0.68+                                    |
| PDF reports          | `pdf` + `printing`                                  |
| Sharing / CSV export | `share_plus`                                        |
| File paths           | `path` + `path_provider`                            |
| IDs                  | `uuid` v4                                           |
| Collections          | `collection` (firstWhereOrNull, etc.)               |

---

## 3. High-level architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          UI (Flutter widgets)                        │
│                                                                      │
│  Dashboard · Projects · Parties · Transactions · Reports · Settings  │
│                                                                      │
└────────────────────────────┬─────────────────────────────────────────┘
                             │   ConsumerWidget / WidgetRef
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  Riverpod providers  (lib/providers/)                │
│                                                                      │
│   dbProvider · ledgerRepoProvider · entityRepoProvider               │
│   backupServiceProvider · backupBootCheckProvider                    │
│   accountSummaryProvider · projectsProvider · …                      │
└──────────┬───────────────────────────────┬───────────────────────────┘
           │                               │
           ▼                               ▼
┌──────────────────────┐       ┌───────────────────────┐
│    Repositories      │       │     Services          │
│                      │       │                       │
│  LedgerRepository    │       │  BackupService        │
│  EntityRepository    │       │  (local file backup)  │
└──────────┬───────────┘       └───────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Local SQLite  (LocalDb)                          │
│       — single source of truth, double-entry general ledger —        │
└──────────────────────────────────────────────────────────────────────┘
```

**Key architectural rules**

1. **Local DB is the only source of truth.** No data is read from any external service at runtime.
2. **All ledger writes go through `LedgerRepository`.** This is the only class that writes to `journal_entries`. Direct DB access from screens is forbidden.
3. **All audit events go through `change_log`.** Every soft delete / restore / archive / unarchive writes a `ChangeLog` row stamped with `device_id`.
4. **Repository-layer validation.** `_assertNonEmpty` guards all required FK fields (`projectId`, `supplierId`) before any `_post()` call, so programming mistakes are caught early regardless of what the UI does.

---

## 4. Project layout

```
lib/
├── main.dart                           # entry point, ProviderScope
├── app.dart                            # MaterialApp + boot provider watchers
├── core/
│   ├── constants.dart                  # Chart of Accounts, enums, settings keys
│   ├── formatters.dart                 # fmtMoney, fmtDate, fmtSignedMoney
│   └── theme.dart                      # Light/dark + BalanceColors
├── data/
│   ├── db/
│   │   └── local_db.dart               # sqflite open + schema v11 + migrations
│   ├── models/                         # Plain Dart structs + toMap/fromMap
│   │   ├── journal_entry.dart
│   │   ├── change_log.dart
│   │   ├── project.dart
│   │   ├── party.dart                  # customers & suppliers
│   │   ├── bank.dart
│   │   ├── counter_entity.dart
│   │   ├── material_item.dart
│   │   ├── material_type_def.dart      # user-defined material catalog
│   │   └── labour_type_def.dart        # user-defined labour categories
│   ├── repositories/
│   │   ├── ledger_repository.dart      # journal_entries writes + reads + all reports
│   │   └── entity_repository.dart      # projects / parties / banks / settings
│   └── services/
│       └── backup_service.dart         # local file backup, 6 h cold-boot trigger
├── providers/
│   └── providers.dart                  # Riverpod wiring for the whole app
└── features/
    ├── home/                           # Bottom-nav shell
    ├── dashboard/                      # Treasury, summary tiles, recent activity, daily spend
    ├── transactions/                   # Txn picker, form, history (date-grouped), detail
    ├── projects/                       # List, detail, reconciliation / archive flow
    ├── parties/                        # Suppliers, banks/wallets, counter entities
    ├── reports/                        # All report screens + CSV + PDF + charts
    │   ├── reports_screen.dart
    │   ├── income_statement_screen.dart    # LR / WM aware, customer deposits section
    │   ├── balance_sheet_screen.dart
    │   ├── cash_flow_screen.dart
    │   ├── aging_analysis_screen.dart
    │   ├── project_bva_screen.dart         # Budget pie, material pie, spend-over-time bar
    │   ├── project_profitability_screen.dart  # Summary table + net-profit bar chart
    │   ├── wage_register_screen.dart
    │   ├── charts_screen.dart              # Burn / Price trend / Cash position / Liquidity
    │   ├── supplier_ledger_screen.dart
    │   ├── material_supplier_ledger_screen.dart
    │   ├── bank_ledger_screen.dart
    │   ├── pdf_generator.dart
    │   └── csv_export.dart
    └── settings/                       # Theme, backup config, audit log, material/labour types
```

---

## 5. Data model

The local SQLite schema is currently at **version 11**. Migrations are forward-only and additive.

### 5.1 `journal_entries` — the ledger

| column          | type      | notes                                                    |
| --------------- | --------- | -------------------------------------------------------- |
| id              | TEXT PK   | uuid v4                                                  |
| transaction_id  | TEXT      | groups the two rows of a single posting                  |
| account_id      | TEXT      | matches an `Account.id` from the Chart of Accounts       |
| project_id      | TEXT?     | FK → projects(id), nullable                              |
| supplier_id     | TEXT?     | FK → suppliers(id), nullable                             |
| customer_id     | TEXT?     | nullable (legacy field)                                  |
| debit, credit   | REAL      | exactly one is non-zero per row                          |
| description     | TEXT?     | free text                                                |
| created_at      | TEXT      | ISO-8601 UTC                                             |
| synced          | INT       | 0 = local only, 1 = confirmed persisted                  |
| is_deleted      | INT       | soft-delete flag (0/1)                                   |
| deleted_at      | TEXT?     | set when soft-deleted                                    |

Every business transaction inserts **exactly two rows** sharing the same `transaction_id` (one debit + one credit, equal amounts). `LedgerRepository._post()` is the only entry point for writes, enforcing this invariant.

v11 added `REFERENCES projects(id)` and `REFERENCES suppliers(id)` FK constraints. The migration nulls out any orphaned references (from historical hard-deletes) before recreating the table.

### 5.2 `change_log` — audit trail

`{id, entity_type, entity_id, action, original_data (JSON), new_data (JSON), note, device_id, timestamp}`

Recorded for: soft delete, restore, archive, unarchive, hard delete. `device_id` is a stable per-install UUID generated on first run and stored in `app_settings`.

### 5.3 Other tables

| Table               | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `projects`          | Name, model (with_material / labour_rate), status, client_name, site_address, budget, project_manager, service_fee_percent, archival fields |
| `suppliers`         | Name, phone, category, tax_status, bank_details, archival fields        |
| `banks`             | User-defined wallets/bank accounts; archival supported                  |
| `counter_entities`  | External receivables / payables not tracked transactionally             |
| `material_inventory`| Per-purchase rows (project, supplier, type, qty, rate, cost, txn_type) used for BvA + price-trend |
| `material_types`    | User-defined material catalog (name, UoM, coverage rate, waste factor, lead days) |
| `labour_types`      | User-defined labour categories (name, description, default daily rate) |
| `app_settings`      | Opaque `{key, value}` — theme, last backup timestamp, device_id         |

### 5.4 Chart of Accounts (`core/constants.dart` → `Accounts`)

| Type      | Account ID           | Display name          | Notes                                    |
| --------- | -------------------- | --------------------- | ---------------------------------------- |
| Asset     | `CASH`               | Cash                  | Physical cash on hand                    |
| Asset     | `SUPERVISOR_FLOAT`   | Supervisor Float      | Site petty-cash float                    |
| Asset     | *(bank row id)*      | *(bank name)*         | Every row in the `banks` table becomes a cash-like account dynamically |
| Liability | `SUPPLIER_PAY`       | Supplier Payables     | Bills incurred, not yet settled          |
| Income    | `PROJECT_REV`        | Project Revenue       | Money received from client               |
| Income    | `SERVICE_FEE`        | Service Fee Income    | Contractor's earned fee (LR projects)    |
| Expense   | `MATERIAL_COSTS`     | Material Costs        | Raw material purchases                   |
| Expense   | `LABOUR_COSTS`       | Labour Costs          | Worker wages (cash or accrued)           |
| Expense   | `PERSONAL_DRAW`      | Personal / Daily Draw | Owner drawings not tied to a project     |
| Equity    | `OWNERS_EQUITY`      | Owner's Equity        | Opening balances                         |

`Accounts.systemCashLike` (Cash + Supervisor Float) plus every row in the `banks` table form the set of **cash-like accounts**. `liquidCash` is the sum of all of them.

---

## 6. Transaction kinds

Each `postXxx` method on `LedgerRepository` maps to one debit/credit pair. The repository validates amount > 0, required FK fields are non-empty, and the source account is cash-like where required.

| Method                 | Debit                | Credit               | Notes                                         |
| ---------------------- | -------------------- | -------------------- | --------------------------------------------- |
| `postMaterialBuy`      | Material Costs       | Supplier Payables    | project_id + supplier_id required             |
| `postLabourPayment`    | Labour Costs         | Cash / Bank          | Cash payment — project_id + supplier_id req.  |
| `postLabourCredit`     | Labour Costs         | Supplier Payables    | Accrual — wages incurred, not yet paid        |
| `postSupplierPay`      | Supplier Payables    | Cash / Bank          | Settles an outstanding payable                |
| `postReceiveFromProject`| Cash / Bank         | Project Revenue      | Client payment in — project_id required       |
| `postWalletTransfer`   | Dest wallet          | Src wallet           | Both must be cash-like; src ≠ dest            |
| `postPersonalDraw`     | Personal Draw        | Cash / Bank          | Owner withdrawal, not linked to a project     |
| `postServiceFee`       | Cash / Bank          | Service Fee Income   | Interim fee receipt — project_id required     |
| `postProjectServiceFee`| Project Revenue      | Service Fee Income   | LR close: reclassifies fee; no cash movement  |
| `postOpeningBalance`   | Bank / Wallet        | Owner's Equity       | Initial balance for a new account             |
| `postReversal`         | *(mirror of original)* | *(mirror)*         | Offsetting entry; original remains in ledger  |

---

## 7. Reporting engine

All financial calculations are SQL aggregates over `journal_entries` (always excluding `is_deleted = 1` rows) in `LedgerRepository`.

### 7.1 Dashboard snapshot — `accountSummaryProvider`

```
liquidCash     = Cash + Supervisor Float + Σ(bank balances)
netLiquidity   = liquidCash − supplierPayables
netPosition    = counterReceivables − (payables + counterPayables)
totalNetWorth  = liquidCash + netPosition
```

### 7.2 Income Statement — `income_statement_screen.dart`

Separates With-Material and Labour-Rate projects by design:

- **With-Material**: Revenue = `min(received, budget)` per project. Anything over budget is shown as "Customer Deposit owed back" (orange informational section, not P&L).
- **Labour-Rate**: Revenue = service fee income only. The pass-through amount (received − fee − costs paid) is shown as "Customer Deposit owed back", never as profit.
- **Service fees** — earned income across all project types.
- **Personal Draw** — shown as an expense line (all-project view only).

### 7.3 Other statements

- **Balance Sheet** — Assets vs Liabilities + Equity, with a balanced/unbalanced indicator.
- **Cash Flow** — `monthlyCashFlow(monthsBack=12)` bucketed by operating / financing / other.
- **Aging Analysis** — FIFO open-balance matcher per party, bucketed 0-30 / 31-60 / 61-90 / 90+ days. Covers both project receivables and supplier payables.
- **Budget vs Actual** — actual spend per material type (from `material_inventory`) + labour vs `Project.budget`. Includes three charts (see §7.4).
- **Project Profitability** — one row per project: received, spent, net. With-Material net = `received − spent`; Labour-Rate net = `feeIncome`. Includes a bar chart.
- **Wage Register** — labour debits grouped by supplier (worker), with payment count and last-paid date.
- **Supplier / Bank / Material Supplier Ledger** — running balance for one party, project-filterable, date-filterable.

### 7.4 Charts

| Chart | Screen | Data source |
| ----- | ------ | ----------- |
| Budget allocation pie | BvA | Material total vs Labour vs Remaining budget |
| Material breakdown pie | BvA | `bva.materialByType` + `bva.otherMaterial` per type |
| Spending over time (Day/Week/Month toggle) | BvA | `projectDailySpend(projectId)` aggregated in-widget |
| Net profit bar | Profitability | `net` per `_ProfitabilityRow`; positive = primary color, negative = error color |
| Burn curve | Charts screen | `projectBurn(projectId)` — cumulative spend line + budget line |
| Price trend | Charts screen | `material_inventory.rate` per type over time |
| Cash position | Charts screen | Stacked bars per cash-like account |
| Liquidity gauge | Charts screen | `liquidCash / payables` coverage ratio |

### 7.5 Exports

- **PDF** — `pdf_generator.dart` (Income Statement, Balance Sheet, Supplier Ledger).
- **CSV** — `csv_export.dart` (RFC-4180 quoted; temp file → `share_plus`). Available on every statement screen.

---

## 8. Backup architecture

All data lives exclusively in the local SQLite database. The backup system makes file copies of that database.

### 8.1 Local file backup — `BackupService`

- Output directory on Android: `<ExternalDocuments>/Bismillah_Backups/` — survives app uninstall.
- Output directory on desktop/iOS fallback: `<AppDocuments>/Bismillah_Backups/`.
- **Two files** written each run:
  - `solo_con_<UTC-stamp>.db` — timestamped snapshot.
  - `solo_con_latest.db` — always overwrites; one-tap share target.
- Writes use an atomic `write-to-tmp → rename` pattern. A crash during copy leaves only an orphaned `.tmp`, never a corrupted destination file.
- **Retention** — last 30 timestamped snapshots kept; older ones pruned automatically.
- `maybeRunSilentBackup()` gates on `last_backup_at` setting (≥ 6 h).
- `shareBackup()` triggers the system share sheet (WhatsApp / Gmail / Drive).
- `importBackup(path)` — validates the SQLite header, saves `.before_import` rollback copy, then atomically overwrites the live DB.
- `rollbackLastImport()` — reinstates the `.before_import` file.

---

## 9. Audit & traceability

Because permissions are flat, **the audit log is the only forensic trail**.

- Every `softDeleteTransaction`, `restoreTransaction`, `hardDeleteTransaction`, `archiveProject`, `unarchiveProject` writes a row to `change_log`.
- Each row carries the install's stable `device_id` (UUID v4, generated on first run, stored in `app_settings`).
- The Settings → **Change Log** screen lists every event newest-first, with a CSV export.

---

## 10. Configuration

### 10.1 In-app settings (`Settings` screen)

- **Theme** — System / Light / Dark
- **Backup** — last backup timestamp, Run backup now, Export / Share latest backup, Import backup
- **Audit** — Change Log viewer
- **Material Types** — add / edit / delete user-defined material categories (catalog used across all projects)
- **Labour Types** — add / edit / delete user-defined labour categories (e.g. Mason, Electrician)

### 10.2 Build-output relocation (Windows + OneDrive)

If your project lives inside a OneDrive-synced folder, the Android build can fail with a permission error. Set `BISMILLAH_BUILD_DIR` to a path outside OneDrive before building:

```powershell
$env:BISMILLAH_BUILD_DIR = "C:\bismillah-build"
flutter build apk --release
```

`android/build.gradle.kts` honours this env var.

---

## 11. Build & run

### 11.1 Prerequisites

- Flutter SDK 3.x with Dart 3.11.5+
- Android SDK 34 — `compileSdk` is pinned in `android/build.gradle.kts`
- For desktop: Visual Studio 2022 build tools (Windows)

### 11.2 Quick start

```bash
flutter pub get
flutter run                  # connected phone / emulator
flutter run -d windows       # Windows desktop
```

### 11.3 Release builds

```bash
# Android APK (universal)
flutter build apk --release

# Smaller per-ABI APKs
flutter build apk --release --split-per-abi

# AAB for Play Store
flutter build appbundle --release

# Windows desktop
flutter build windows --release
```

Signed APK: `build/app/outputs/flutter-apk/app-release.apk`

---

## 12. App boot sequence

1. `main.dart` — `WidgetsFlutterBinding.ensureInitialized()` → `runApp(ProviderScope(SoloConApp))`.
2. `app.dart` builds `MaterialApp` and **eagerly watches** three boot providers:
   - `backupBootCheckProvider` — runs the silent local backup if ≥ 6 h since last.
   - `commitSyncWiringProvider` — reserved; wires commit listeners.
   - `themeModeProvider` — restores the saved theme from `app_settings`.
3. `LocalDb.instance.open()` runs migrations to the current schema version (v11).

---

## 13. Schema migration history

| Version | Changes |
| ------- | ------- |
| v1      | Initial schema: customers, suppliers, projects, journal_entries, change_log, app_settings |
| v2      | Added ntn_cnic / address / credit_limit on customers; category / tax_status / bank_details on suppliers; customer_id / site_address / budget / project_manager on projects; banks + counter_entities + material_inventory tables |
| v3      | Soft delete (is_deleted / deleted_at) on journal_entries; service_fee_percent / is_archived / archived_at on projects; change_log + app_settings |
| v4      | device_id on change_log |
| v5      | client_name (free-text) on projects; seeded legacy hardcoded bank ids if referenced |
| v6      | is_archived / archived_at on suppliers and banks |
| v7      | material_types table (user-defined catalog, empty on fresh install) |
| v8      | Procurement metadata on material_types (uom_typ, uom, cov_rate, waste_f, lead_d, dims) |
| v9      | Removed seeded built-in material types — user defines every type from scratch |
| v10     | labour_types table |
| v11     | Added `REFERENCES projects(id)` and `REFERENCES suppliers(id)` FK constraints on journal_entries via table recreation; orphaned references nulled before migration |

---

## 14. Coding conventions

- Repositories never import `package:flutter/*`. Pure Dart — easy to unit-test.
- Models are plain classes with `toMap()` / `fromMap()` / `const` constructors. No code generation.
- Screens use `ConsumerWidget` / `ConsumerStatefulWidget`. State that triggers data re-fetch goes through `ledgerVersionProvider` (`bumpLedger(ref)` after any mutation).
- Money is stored as `REAL` (double) in SQLite and formatted via `fmtMoney` / `fmtSignedMoney`. PKR, no decimal digits in the UI.
- Times stored as ISO-8601 UTC strings; converted to local time for display via `fmtDate` / `fmtDateTime`.
- Positive/negative coloring uses `BalanceColors.signed(context, value)` — never hard-coded `Colors.green` / `Colors.red`.
- Comments reserved for the *why* (constraints, invariants, surprising behavior) — never the *what*.
- Chart colors: orange = material, blue = labour, green = remaining/positive, red = overrun/negative.

---

## 15. License

Internal — © Bismillah Constructions.
