# Bismillah Constructions ERP

> Solo-Con ERP — an offline-first, double-entry construction-project ledger built in Flutter.
> Designed for a single operator running multiple sites: cash, bank, supplier, customer, material, labour, and project P&L all in one place, with redundant local + cloud backups.

---

## 1. What the application does

Bismillah Constructions ERP is a desktop / mobile / Android-tablet app that records every rupee that moves through a small-to-mid construction business and turns it into reports the owner can use to make decisions.

It supports two contract models simultaneously:

| Model            | Profit formula                                        | Use when                                                                  |
| ---------------- | ----------------------------------------------------- | ------------------------------------------------------------------------- |
| **With-Material**| `Profit = Σ(Customer Inflow) − Σ(Project Outflow)`    | The business buys materials and pays labour itself; profit = leftover.    |
| **Labour-Rate**  | `Profit = Σ(Total Project Spend) × Service Fee %`    | The business is a pass-through; it earns a fixed % service fee.           |

Every cash movement is recorded as a balanced **debit/credit pair** on a fixed Chart of Accounts, so reports (Income Statement, Balance Sheet, Cash Flow) come out correct by construction.

### Headline feature list

- **Transactions** — 8 canonical kinds (Material Buy, Labour Payment, Supplier Pay, Client Billing, Receive Payment, Wallet Transfer, Personal Draw, Service Fee). Each one posts a guaranteed-balanced journal entry.
- **Reconciliation gate** — With-Material projects can only be archived when `Customer Inflow == Supplier Paid + Supplier Payables`. Labour-Rate projects skip the check (pass-through).
- **Soft delete + reversal** — every delete is reversible; reversals post offsetting transactions.
- **Audit log** — every edit/delete/archive records `{timestamp, action, oldData, newData, deviceId, note}`.
- **Dual-layered backup** — local file backup every 6 h **plus** MongoDB cloud snapshot debounced 5 s after every commit (auto-uploads when online).
- **Reports** — Income Statement, Balance Sheet, Cash Flow, Aging (0-30 / 31-60 / 61-90 / 90+), Budget vs Actual, Wage Register, Supplier Ledger, Customer Ledger.
- **Charts** — Burn (cumulative spend vs budget), Price Trend (Steel / Cement / Bricks), Cash Position (stacked banks vs site floats), Liquidity Gauge (circular dial).
- **Exports** — every statement exports to **CSV** and the major ones to **PDF**.
- **Theme** — Light / Dark / System, blue = positive, red = negative.
- **Flat permissions** — single-operator app; no roles, no PIN.

---

## 2. Tech stack

| Concern                | Choice                                              |
| ---------------------- | --------------------------------------------------- |
| Language / runtime     | Dart 3.11.5, Flutter 3.x                            |
| State management       | `flutter_riverpod` 2.x                              |
| Local DB               | `sqflite` + `sqflite_common_ffi` (desktop)          |
| Connectivity           | `connectivity_plus`                                 |
| Charts                 | `fl_chart`                                          |
| PDF reports            | `pdf` + `printing`                                  |
| Sharing / CSV export   | `share_plus`                                        |
| File paths             | `path` + `path_provider`                            |
| Hashing (snapshots)    | `crypto` (SHA-1 of DB blob)                         |
| IDs                    | `uuid` v4                                           |

---

## 3. High-level architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                          UI (Flutter widgets)                      │
│                                                                    │
│  Dashboard · Projects · Parties · Transactions · Reports · Charts  │
│                                                                    │
└──────────────────────────────┬─────────────────────────────────────┘
                               │   ConsumerWidget / WidgetRef
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│                  Riverpod providers (lib/providers/)               │
│                                                                    │
│   dbProvider · ledgerRepoProvider · entityRepoProvider             │
│   syncServiceFutureProvider · mongoBackupServiceProvider           │
│   commitSyncWiringProvider · backupBootCheckProvider               │
│   accountSummaryProvider · projectsProvider · …                    │
└──────────┬─────────────────┬────────────────────┬──────────────────┘
           │                 │                    │
           ▼                 ▼                    ▼
┌──────────────────┐ ┌─────────────────┐ ┌─────────────────────────┐
│  Repositories    │ │  Services       │ │  External services      │
│                  │ │                 │ │                         │
│  LedgerRepository│ │  BackupService  │ │  Supabase (rows)        │
│  EntityRepository│ │  SyncService    │ │  MongoDB (snapshots)    │
│                  │ │  MongoBackupSvc │ │                         │
└─────────┬────────┘ └────────┬────────┘ └─────────────────────────┘
          │                   │
          ▼                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                       Local SQLite (LocalDb)                       │
│        — single source of truth, double-entry general ledger —     │
└────────────────────────────────────────────────────────────────────┘
```

**Key architectural rules**

1. **Local DB is the source of truth.** Everything written to Supabase / MongoDB is a *copy*; nothing is read back from the cloud at runtime.
2. **All ledger writes go through `LedgerRepository`.** This is the only class that calls `db.insert('journal_entries', …)`. Direct DB access from screens is forbidden.
3. **All audit events go through `change_log`.** Every soft delete / restore / archive / unarchive writes a `ChangeLog` row stamped with `device_id`.
4. **Listeners, not callers, trigger sync.** `LedgerRepository` exposes commit listeners; `commitSyncWiringProvider` attaches the sync services. Repository code knows nothing about sync.

---

## 4. Project layout

```
lib/
├── main.dart                           # ProviderScope + Supabase.initialize()
├── app.dart                            # MaterialApp + bootstraps providers
├── core/
│   ├── constants.dart                  # Chart of Accounts, enums, settings keys
│   ├── formatters.dart                 # fmtMoney, fmtDate, fmtSignedMoney
│   └── theme.dart                      # Light/dark + BalanceColors
├── data/
│   ├── db/
│   │   └── local_db.dart               # sqflite open + schema + migrations
│   ├── models/                         # Plain Dart structs + toMap/fromMap
│   │   ├── journal_entry.dart
│   │   ├── change_log.dart
│   │   ├── project.dart
│   │   ├── party.dart   (customers & suppliers)
│   │   ├── bank.dart
│   │   ├── counter_entity.dart
│   │   └── material_item.dart
│   ├── repositories/
│   │   ├── ledger_repository.dart      # journal_entries writes + reads + reports
│   │   └── entity_repository.dart      # projects / parties / banks / settings
│   ├── services/
│   │   ├── backup_service.dart         # local file backup, 6 h cold-boot trigger
│   │   └── mongo_backup_service.dart   # MongoDB cloud snapshot, debounced
│   └── sync/
│       └── sync_service.dart           # Supabase row push (journal_entries)
├── providers/
│   └── providers.dart                  # Riverpod wiring for the whole app
└── features/
    ├── home/                           # Bottom-nav shell
    ├── dashboard/                      # Treasury, P&L summary, recent activity
    ├── transactions/                   # New txn picker, form, history, detail
    ├── projects/                       # List, detail, reconciliation/archive
    ├── parties/                        # Customers, suppliers, banks, counters
    ├── reports/                        # All 9 report screens + CSV + PDF + charts
    │   ├── reports_screen.dart
    │   ├── income_statement_screen.dart
    │   ├── balance_sheet_screen.dart
    │   ├── cash_flow_screen.dart
    │   ├── aging_analysis_screen.dart
    │   ├── project_bva_picker_screen.dart  + project_bva_screen.dart
    │   ├── wage_register_screen.dart
    │   ├── charts_screen.dart              (Burn / Price / Cash / Liquidity)
    │   ├── supplier_ledger_*.dart          + customer_ledger_screen.dart
    │   ├── pdf_generator.dart              (PDF layout helpers)
    │   └── csv_export.dart                 (RFC-4180 CSV + share sheet)
    └── settings/                       # Theme, backup config, change log viewer
```

---

## 5. Data model

The local SQLite schema (currently version **4**) has 9 tables. Migrations are forward-only and additive.

### 5.1 `journal_entries` — the ledger
| column          | type     | notes                                           |
| --------------- | -------- | ----------------------------------------------- |
| id              | TEXT PK  | uuid v4                                         |
| transaction_id  | TEXT     | groups the two rows of a single posting         |
| account_id      | TEXT     | matches a `Account.id` from `Accounts` (CoA)    |
| project_id      | TEXT?    | nullable                                        |
| supplier_id     | TEXT?    | nullable                                        |
| customer_id     | TEXT?    | nullable                                        |
| debit, credit   | REAL     | exactly one is non-zero                         |
| description     | TEXT?    | free text                                       |
| created_at      | TEXT     | ISO-8601 UTC                                    |
| synced          | INT      | 0 = not pushed to Supabase yet                  |
| is_deleted      | INT      | soft delete flag                                |
| deleted_at      | TEXT?    |                                                  |

Every business transaction inserts **two** rows with the same `transaction_id` (one debit + one credit, equal amounts). This is enforced by `LedgerRepository._post()` and is the only place that writes to this table.

### 5.2 `change_log` — audit trail
`{id, entity_type, entity_id, action, original_data (JSON), new_data (JSON), note, device_id, timestamp}`

Recorded for: delete, restore, archive, unarchive, edit. `device_id` is a stable per-install UUID generated on first run.

### 5.3 Other tables
- `projects` — `{id, name, model (with_material|labour_rate), status, customer_id, site_address, budget, project_manager, service_fee_percent, is_archived, archived_at, created_at}`
- `customers`, `suppliers` — `Party` rows with category / tax_status / bank_details fields
- `banks`, `counter_entities` — supporting entities
- `material_inventory` — purchase / consumption rows (used for BvA + price-trend charts)
- `app_settings` — opaque `{key, value}` for theme, backup timestamps, mongo URI, device_id, etc.

### 5.4 Chart of Accounts (`core/constants.dart` → `Accounts`)

| Type        | Accounts                                                                                      |
| ----------- | --------------------------------------------------------------------------------------------- |
| Asset       | Cash, Bank-HBL, Bank-Meezan, Bank-Alfalah, Supervisor Float, External Wallet, Client Receivables, Counter Receivables |
| Liability   | Supplier Payables, Counter Payables                                                           |
| Income      | Project Revenue, Service Fee Income                                                           |
| Expense     | Material Costs, Labour Costs, Personal / Daily Draw                                            |
| Equity      | Owner's Equity                                                                                |

`Accounts.cashLikeAccounts` (Cash + 3 Banks + Supervisor Float) defines the wallets that count toward `Liquid_Cash`.

---

## 6. Transaction kinds — the only writes that matter

Defined as `TxnKind` in `core/constants.dart`. Each maps to exactly one debit/credit pair.

| Kind             | Debit                  | Credit                   |
| ---------------- | ---------------------- | ------------------------ |
| materialBuy      | Material Costs         | Supplier Payables        |
| labourPayment    | Labour Costs           | Cash / Bank              |
| supplierPay      | Supplier Payables      | Cash / Bank              |
| clientBilling    | Client Receivables     | Project Revenue          |
| receivePayment   | Cash / Bank            | Client Receivables       |
| walletTransfer   | Destination wallet     | Source wallet            |
| personalDraw     | Personal Draw          | Cash / Bank              |
| serviceFee       | Cash / Bank            | Service Fee Income       |

The repository validates: amount > 0, source account is in `cashLikeAccounts` where required, source ≠ destination on transfers, etc.

---

## 7. Reporting engine

All financial calculations come out of `LedgerRepository` SQL aggregates over `journal_entries` (excluding soft-deletes).

### 7.1 Always-on snapshot — `accountSummaryProvider`
Computes every dashboard / balance-sheet number in a single pass:

```text
liquidCash      = cash + bankHbl + bankMeezan + bankAlfalah + supervisorFloat
netLiquidity    = liquidCash − supplierPayables           // cash truly free to spend
assets          = liquidCash + receivables + counterReceivables
liabilities     = supplierPayables + counterPayables
netProfit       = (revenue + serviceFeeIncome) − (materialCosts + labourCosts + personalDraw)
equity          = assets − liabilities
totalNetWorth   = liquidCash + (receivables + counterReceivables − liabilities)
```

### 7.2 Statements
- **Income Statement** — `creditBalance(PROJECT_REV) − accountBalance(MATERIAL_COSTS) − accountBalance(LABOUR_COSTS)` (project-filterable).
- **Balance Sheet** — Assets vs Liabilities + Equity, with a balanced/unbalanced banner.
- **Cash Flow** — `monthlyCashFlow(monthsBack=12)` returns `[month → {accountId → Δ}]` for the 5 cash-like accounts.
- **Aging Analysis** — FIFO open-balance matcher per party, bucketed `0-30 / 31-60 / 61-90 / 90+` days. Works for both receivables and payables.
- **Budget vs Actual** — actual spend per `MaterialType` (from `material_inventory`) + Labour, compared against `Project.budget`.
- **Wage Register** — labour debits grouped by supplier (worker), with payment counts and last-paid date.
- **Supplier / Customer Ledger** — running balance for one party, project-filterable.

### 7.3 Charts (`features/reports/charts_screen.dart`, `fl_chart`)
- **Burn Chart** — line of cumulative project outflow + dashed budget line.
- **Price Trend** — line per material type using `material_inventory.rate` over time.
- **Cash Position** — two stacked bars (Banks vs Site Floats).
- **Liquidity Gauge** — circular `CircularProgressIndicator` showing `liquidCash / payables` coverage, centre label = `Net Liquidity`.

### 7.4 Exports
- **PDF** — `pdf_generator.dart` (Income Statement, Balance Sheet, Supplier Ledger).
- **CSV** — `csv_export.dart` (RFC-4180 quoted; writes to temp dir; triggers `share_plus`). Hooked into every statement screen.

---

## 8. Backup & sync architecture

There are **three** independent persistence layers, each with a different role:

| Layer                | What it stores                | Trigger                                       | Failure mode                          |
| -------------------- | ----------------------------- | --------------------------------------------- | ------------------------------------- |
| Local SQLite         | All live data                 | Every write                                   | App can't function (source of truth)  |
| Local file backup    | Full `.db` file copy          | Cold-boot if last >6 h, or manual             | Survives uninstall on Android         |

### 8.1 Local file backup — `BackupService`
- Output dir on Android: `/Documents/Bismillah_Backups/` (external Documents — survives uninstall).
- Output dir on desktop: `<AppDocuments>/Bismillah_Backups/`.
- Two files written each run: `solo_con_<UTC-stamp>.db` + a rolling `solo_con_latest.db` for fast share/import.
- `maybeRunSilentBackup()` gates on `last_backup_at` setting (≥ 6 h since last).
- `shareBackup()` triggers system share sheet for portable .db hand-off.
- `importBackup(path)` saves a `.before_import` safety copy then overwrites the live DB.


### 8.3 Per-commit wiring — `commitSyncWiringProvider`
```dart
ledger.addCommitListener(() {
  cloud.scheduleUpload();   // MongoDB snapshot, debounced
  unawaited(sync.syncNow()); // Supabase row push
});
```
Watched once at app boot from `app.dart`.

---

## 9. Audit & traceability

Because permissions are flat, **the audit log is the only forensic trail**.

- Every `softDeleteTransaction` / `restoreTransaction` / `archiveProject` / `unarchiveProject` / `logChange` call writes a row to `change_log`.
- Each row carries the install's stable `device_id` (UUID v4 generated on first run, stored in `app_settings`).
- The Settings → **Change Log** screen lists every event newest-first, with a CSV export.

---

## 10. Configuration

### 10.1 Optional environment toggles (passed at `flutter run` / build time)
```bash
--dart-define=SUPABASE_URL=https://xxx.supabase.co
--dart-define=SUPABASE_ANON_KEY=eyJ…
```
If unset, the app runs **local-only** and the dashboard sync indicator shows "Local".

### 10.2 In-app configuration (`Settings` screen)
- **Theme** — System / Light / Dark
- **Backup** — last backup timestamp, Run backup now, Export / Share latest backup
- **Audit** — Change Log viewer

### 10.3 Build-output relocation (Windows + OneDrive)
If your project lives inside a OneDrive-synced folder, set `BISMILLAH_BUILD_DIR` to an absolute path **outside** OneDrive before building, otherwise Gradle's `mergeReleaseNativeLibs` will fail with `AccessDeniedException`.

```powershell
$env:BISMILLAH_BUILD_DIR = "C:\bismillah-build"
flutter build apk --release
```

`android/build.gradle.kts` honours this env var (see top of that file for the exact logic).

---

## 11. Build & run

### 11.1 Prerequisites
- Flutter SDK 3.x with Dart 3.11.5+
- Android SDK 34 (or higher) — `compileSdk` is forced to 34 for all subprojects in `android/build.gradle.kts`
- For desktop: Visual Studio 2022 build tools (Windows) or equivalent

### 11.2 Quick start
```bash
flutter pub get
flutter run                 # picks the connected device / emulator
```

### 11.3 Release builds
```bash
# Android APK (universal, ~60 MB)
flutter build apk --release

# Smaller per-ABI APKs
flutter build apk --release --split-per-abi

# AAB for Play Store
flutter build appbundle --release

# Windows desktop
flutter build windows --release
```

The signed APK lands at:
`build/app/outputs/flutter-apk/app-release.apk` (or under `BISMILLAH_BUILD_DIR` if set).

---

## 12. App boot sequence

1. `main.dart` — `WidgetsFlutterBinding.ensureInitialized()` → `Supabase.initialize(…)` if env vars are set → `runApp(ProviderScope(SoloConApp))`.
2. `app.dart` builds `MaterialApp` and **eagerly watches** four boot providers so they spin up immediately:
   - `syncServiceFutureProvider` — starts Supabase ticker + connectivity listener.
   - `backupBootCheckProvider` — runs the >6 h silent local backup if due.
   - `commitSyncWiringProvider` — attaches the cloud-sync commit listener.
   - `themeModeProvider` — restores the saved theme.
3. `LocalDb.instance.open()` runs migrations (currently v3 → v4 adds `device_id` to `change_log`).

---

## 13. Coding conventions

- Repositories never import `package:flutter/*`. Pure Dart, easy to unit-test.
- Models are plain classes with `toMap()` / `fromMap()` / `const` constructors. No `json_serializable`.
- Screens use `ConsumerWidget` / `ConsumerStatefulWidget`. State that triggers re-fetch goes through `ledgerVersionProvider` (`bumpLedger(ref)` after any mutation).
- Money is stored as `REAL` (double) in SQLite and formatted via `fmtMoney` / `fmtSignedMoney`. PKR currency, locale `en_PK`, no decimal digits in the UI.
- Times are stored as ISO-8601 UTC strings; converted to local for display via `fmtDate` / `fmtDateTime`.
- Green / red coloring uses `BalanceColors.signed(context, value)` — never hard-coded `Colors.green` / `Colors.red`, so dark mode stays legible.
- Comments are reserved for the *why* (constraints, invariants, surprising behavior) — not the *what*.

---

## 14. License

Internal — © Bismillah Constructions. Open-source.


