# Bismillah Constructions ERP — Technical Reference

Engineering documentation for the Flutter + SQLite construction-accounting
app. For end-user help, see [USER_MANUAL.md](USER_MANUAL.md).

---

## 1. Tech stack

| Concern              | Choice                                              |
| -------------------- | --------------------------------------------------- |
| Language / runtime   | Dart 3.11.5+, Flutter 3.x                           |
| State management     | `flutter_riverpod` 2.x                              |
| Local DB             | `sqflite` + `sqflite_common_ffi` (desktop / tests)  |
| Charts               | `fl_chart` 0.68+                                    |
| PDF reports          | `pdf` + `printing`                                  |
| Sharing / file pick  | `share_plus` + `file_picker`                        |
| File paths           | `path` + `path_provider`                            |
| IDs                  | `uuid` v4                                           |
| Collections          | `collection` (firstWhereOrNull, etc.)               |
| Tests                | `flutter_test` + `sqflite_common_ffi` in-memory DB  |

No cloud SDK, no auth, no analytics — fully offline-first.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          UI (Flutter widgets)                        │
│                                                                      │
│  Dashboard · Manage · Reports · Settings · Transactions · Projects   │
│                                                                      │
└────────────────────────────┬─────────────────────────────────────────┘
                             │   ConsumerWidget / WidgetRef
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  Riverpod providers  (lib/providers/)                │
│                                                                      │
│  db_providers · sync_providers · entity_providers · theme_provider   │
│  ledger_read_providers · account_summary · cash_runway               │
└──────────┬───────────────────────────────┬───────────────────────────┘
           │                               │
           ▼                               ▼
┌──────────────────────┐       ┌───────────────────────┐
│    Repositories      │       │     Services          │
│                      │       │                       │
│  LedgerRepository    │       │  BackupService        │
│  EntityRepository    │       │  ErrorReporter        │
└──────────┬───────────┘       └───────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Local SQLite  (LocalDb)                          │
│       — single source of truth, double-entry general ledger —        │
└──────────────────────────────────────────────────────────────────────┘
```

### Architectural rules

1. **Local DB is the only source of truth.** No data is read from any
   external service at runtime.
2. **All ledger writes go through `LedgerRepository`.** This is the only
   class that writes to `journal_entries`. Direct DB access from screens
   is forbidden.
3. **All audit events go through `change_log`.** Every soft delete,
   restore, archive or unarchive writes a `ChangeLog` row stamped with
   `device_id`.
4. **Repository-layer validation.** `_assertNonEmpty` guards all required
   FK fields (`projectId`, `supplierId`) before any `_post()` call.
5. **One source of truth for P&L.** `LedgerRepository.incomeFigures()`
   computes recognized revenue, costs, deposits and loss provision once;
   the dashboard, Income Statement and BvA all consume it.

---

## 3. Project layout

```
bismillah_constructions/
├── lib/
│   ├── main.dart                              # entry, error handlers, ProviderScope
│   ├── app.dart                               # MaterialApp + boot watchers
│   ├── core/
│   │   ├── app_restart.dart                   # ValueNotifier that rebuilds the tree
│   │   ├── constants.dart                     # Chart of Accounts, enums, settings keys
│   │   ├── error_reporter.dart                # global error log + SnackBar surface
│   │   ├── formatters.dart                    # fmtMoney, fmtCompactMoney, fmtDate
│   │   ├── theme.dart                         # Indigo/Navy theme + BalanceColors
│   │   └── export/
│   │       ├── csv_export.dart                # RFC-4180 CSV builder + share
│   │       └── pdf_generator.dart             # PDF report builder
│   ├── data/
│   │   ├── db/
│   │   │   └── local_db.dart                  # sqflite open + schema v11 + migrations
│   │   ├── models/                            # Plain Dart structs + toMap/fromMap
│   │   ├── repositories/
│   │   │   ├── ledger_repository.dart         # journal_entries writes + reads + reports
│   │   │   ├── ledger_repository_models.dart  # part of — result classes
│   │   │   └── entity_repository.dart         # projects / parties / banks / settings
│   │   ├── services/
│   │   │   └── backup_service.dart            # local file backup, atomic copy
│   │   └── sync/
│   │       └── sync_service.dart              # commit-listener wiring
│   ├── providers/                             # split barrel — providers.dart re-exports
│   │   ├── providers.dart                     # barrel: re-exports the 7 below
│   │   ├── db_providers.dart                  # db, repos, ledgerVersion, bumpLedger
│   │   ├── sync_providers.dart                # sync, backup, boot hooks
│   │   ├── theme_provider.dart                # ThemeModeNotifier
│   │   ├── entity_providers.dart              # projects/suppliers/banks/types lists
│   │   ├── ledger_read_providers.dart         # entries, daily spend, change log
│   │   ├── account_summary.dart               # AccountSummary class + provider
│   │   └── cash_runway.dart                   # CashRunway class + provider
│   └── features/
│       ├── home/                              # Bottom-nav shell + back stack
│       ├── dashboard/                         # Treasury, runway, daily spend, at-risk
│       ├── manage/                            # Projects/Suppliers/Banks tile, types screens
│       ├── transactions/                      # Picker, form, history (date-grouped)
│       ├── projects/                          # List, reconciliation/archive flow
│       ├── parties/                           # Suppliers, banks/wallets
│       ├── reports/                           # All reports + charts
│       ├── common/                            # async_view, date_range_bar, ledger_view, restore_gateway
│       └── settings/                          # Theme, backup, audit, errors, types
└── test/
    ├── invariants_test.dart                   # core engine invariants (13)
    ├── business_logic_test.dart               # PoC, labour-payment, archive gate (31)
    ├── backup_blackbox_test.dart              # backup/restore/persistence (19)
    ├── user_journeys_blackbox_test.dart       # end-to-end flows (10)
    └── widget_test.dart                       # constants/enums (2)
```

Total LOC across `lib/`: ~16,800. Total automated tests: **75**.

---

## 4. Data model

The local SQLite schema is at **version 11**. Migrations are forward-only
and additive. See section [12](#12-schema-migration-history) for the full
migration history.

### 4.1 `journal_entries` — the ledger

| column          | type      | notes                                                    |
| --------------- | --------- | -------------------------------------------------------- |
| id              | TEXT PK   | uuid v4                                                  |
| transaction_id  | TEXT      | groups the two rows of a single posting                  |
| account_id      | TEXT      | matches an `Account.id` from the Chart of Accounts       |
| project_id      | TEXT?     | FK → projects(id), nullable                              |
| supplier_id     | TEXT?     | FK → suppliers(id), nullable                             |
| customer_id     | TEXT?     | nullable (legacy field, post-customer-removal)           |
| debit, credit   | REAL      | exactly one is non-zero per row                          |
| description     | TEXT?     | free text                                                |
| created_at      | TEXT      | ISO-8601 UTC                                             |
| synced          | INT       | 0/1 — committed locally                                  |
| is_deleted      | INT       | soft-delete flag                                         |
| deleted_at      | TEXT?     | set when soft-deleted                                    |

Every business transaction inserts **exactly two rows** sharing the same
`transaction_id` (one debit + one credit, equal amounts).
`LedgerRepository._post()` is the only entry point for writes.

v11 added `REFERENCES projects(id)` / `REFERENCES suppliers(id)` FK
constraints. The migration nulls out orphans before recreating the table.

### 4.2 `change_log` — audit trail

`{id, entity_type, entity_id, action, original_data (JSON), new_data (JSON), note, device_id, timestamp}`

Recorded for: soft delete, restore, archive, unarchive, hard delete.
`device_id` is a stable per-install UUID generated on first run and
stored in `app_settings`.

### 4.3 Other tables

| Table               | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `projects`          | name, model (`withMaterial`/`labourRate`), status, client_name, site_address, budget, project_manager, service_fee_percent, archival fields |
| `suppliers`         | name, phone, category, tax_status, bank_details, archival fields        |
| `banks`             | user-defined wallets/bank accounts; archival supported                  |
| `counter_entities`  | external receivables/payables not tracked transactionally               |
| `material_inventory`| per-purchase rows used for BvA + price-trend                            |
| `material_types`    | user-defined material catalog (name, UoM, coverage rate, waste, lead-d) |
| `labour_types`      | user-defined labour categories (name, description, default daily rate)  |
| `app_settings`      | opaque `{key, value}` — theme, last_backup_at, device_id                |

### 4.4 Chart of Accounts (`core/constants.dart` → `Accounts`)

| Type      | Account ID           | Display name          | Notes                                    |
| --------- | -------------------- | --------------------- | ---------------------------------------- |
| Asset     | `CASH`               | Cash                  | Physical cash on hand                    |
| Asset     | `SUPERVISOR_FLOAT`   | Supervisor Float      | Site petty-cash float                    |
| Asset     | *(bank row id)*      | *(bank name)*         | Each row in the `banks` table is a cash-like account dynamically |
| Liability | `SUPPLIER_PAY`       | Supplier Payables     | Bills incurred, not yet settled          |
| Income    | `PROJECT_REV`        | Project Revenue       | Money received from client               |
| Income    | `SERVICE_FEE`        | Service Fee Income    | Contractor's earned fee (LR projects)    |
| Expense   | `MATERIAL_COSTS`     | Material Costs        | Raw material purchases                   |
| Expense   | `LABOUR_COSTS`       | Labour Costs          | Worker wages (cash or accrued)           |
| Expense   | `PERSONAL_DRAW`      | Personal / Daily Draw | Owner drawings not tied to a project     |
| Equity    | `OWNERS_EQUITY`      | Owner's Equity        | Opening balances                         |

`Accounts.systemCashLike` (Cash + Supervisor Float) plus every row in the
`banks` table form the set of **cash-like accounts**. `liquidCash` is the
sum of all of them.

---

## 5. Transaction kinds

Each `postXxx` method on `LedgerRepository` maps to one debit/credit
pair. The repository validates `amount > 0`, required FK fields, and
that source accounts are cash-like where required.

| Method                    | Debit               | Credit              | Notes                                         |
| ------------------------- | ------------------- | ------------------- | --------------------------------------------- |
| `postMaterialBuy`         | Material Costs      | Supplier Payables   | project_id + supplier_id required             |
| `postLabourPayment`       | *smart, see below*  | Cash / Bank         | project_id + supplier_id required             |
| `postLabourCredit`        | Labour Costs        | Supplier Payables   | Wages incurred, not yet paid                  |
| `postSupplierPay`         | Supplier Payables   | Cash / Bank         | Settles an outstanding payable                |
| `postReceiveFromProject`  | Cash / Bank         | Project Revenue     | Client payment in — project_id required       |
| `postWalletTransfer`      | Dest wallet         | Src wallet          | Both must be cash-like; src ≠ dest            |
| `postPersonalDraw`        | Personal Draw       | Cash / Bank         | Owner withdrawal, not linked to a project     |
| `postServiceFee`          | Cash / Bank         | Service Fee Income  | Interim fee receipt — project_id required     |
| `postProjectServiceFee`   | Project Revenue     | Service Fee Income  | LR close: reclassifies fee; no cash movement  |
| `postOpeningBalance`      | Bank / Wallet       | Owner's Equity      | Initial balance for a new account             |
| `postReversal`            | mirror of original  | mirror              | Offsetting entry; original remains in ledger  |

### 5.1 `postLabourPayment` smart settlement

If the worker has an outstanding wage credit (booked earlier via
`postLabourCredit`), the payment **settles the existing payable first**
rather than creating a new direct cost. Three branches:

- `payment ≤ owed`: posts `Dr Supplier Payables / Cr Cash` only — no
  new cost line.
- `payment > owed`: settles the existing payable in full, then books
  the excess as a fresh `Dr Labour Costs / Cr Cash`. Two transactions
  share the description.
- no outstanding credit: posts `Dr Labour Costs / Cr Cash` directly,
  matching the original behaviour.

This avoids the double-counting bug where labour costs would be doubled
and the payable left untouched.

---

## 6. Reporting engine

All financial calculations are SQL aggregates over `journal_entries`
(always excluding `is_deleted = 1` rows).

### 6.1 `incomeFigures()` — single source of truth

`LedgerRepository.incomeFigures({from, to, projectId})` returns the
canonical P&L bundle used by both the Income Statement and the
dashboard's Net Profit. It implements **Percentage-of-Completion
(cost-recovery variant)**:

- **With-Material, in-progress** (not archived):
  `revenue = min(received, costs_to_date)`. Excess sits as a
  customer-deposit liability.
- **With-Material, closed** (archived):
  `revenue = min(received, budget)`. Anything received over budget is a
  refund-able deposit.
- **Loss provision** (FASB/IFRS): if `costs > budget` on any project,
  `costs - budget` is recognized as an immediate cost line.
- **Labour-Rate**: service fees only as earned income; everything else
  is a customer-deposit liability.
- **Projects at risk**: every project ≥ 80% of budget is flagged for
  the dashboard warning panel, sorted with over-budget jobs first.

### 6.2 Dashboard snapshot — `accountSummaryProvider`

```
liquidCash     = Cash + Supervisor Float + Σ(bank balances)
netLiquidity   = liquidCash − supplierPayables
netPosition    = counterReceivables − (payables + counterPayables)
totalNetWorth  = liquidCash + netPosition
netProfit      = revenue + serviceFee − (matCosts + labCosts + personalDraw + lossProvision)
```

`AccountSummary` also carries `customerDeposits` and the
`projectsAtRisk` list straight from `incomeFigures()`.

### 6.3 `cashRunwayProvider`

```
avgDailyBurn  = Σ(material+labour costs in last 30 days) / distinct_active_days
runwayDays    = liquidCash / avgDailyBurn
```

The active-days denominator (instead of dividing by a fixed 30) means a
single high-spend day yields a meaningful daily rate immediately, not a
diluted "1700-day runway" artefact.

### 6.4 Other statements

- **Balance Sheet** — Assets vs Liabilities + Equity, balanced indicator.
- **Cash Flow** — `monthlyCashFlow(monthsBack=12)` bucketed by operating /
  financing / other.
- **Aging Analysis** — FIFO open-balance matcher per party, bucketed
  0-30 / 31-60 / 61-90 / 90+ days. Covers project receivables and
  supplier payables.
- **Budget vs Actual** — actual spend per material type (from
  `material_inventory`) + labour vs `Project.budget`. Overrun banner
  when `costs > budget`.
- **Project Profitability** — one row per project: received, spent, net.
  Net profit chart with bold zero line.
- **Wage Register** — labour debits grouped by supplier (worker), with
  payment count and last-paid date.
- **Supplier-wise Spending** — total material + labour by supplier,
  filterable by period (all-time / 90 days / 30 days).
- **Supplier / Bank / Project Ledger** — running balance for one party,
  project-filterable, date-filterable.

### 6.5 Charts

| Chart                                       | Screen           | Data source                                                |
| ------------------------------------------- | ---------------- | ---------------------------------------------------------- |
| Budget allocation pie                       | BvA              | Material vs Labour vs Remaining                            |
| Material breakdown pie                      | BvA              | `bva.materialByType` + `bva.otherMaterial`                 |
| Spending over time (Day/Week/Month toggle)  | BvA              | `projectDailySpend(projectId)` aggregated in-widget        |
| Net profit bar                              | Profitability    | `net` per project; emerald above zero, rose below          |
| 7-day spending bar                          | Dashboard        | `overallDailySpend(daysBack: 7)` aggregated to the day     |

All charts use `fmtCompactMoney` for axis labels (Rs 1.5L, Rs 250k, etc.)
with auto-picked "nice" intervals (1/2/5/10 × 10ⁿ).

### 6.6 Exports

- **PDF** — `core/export/pdf_generator.dart` (Income Statement, Balance
  Sheet, Supplier Ledger, Wage Register).
- **CSV** — `core/export/csv_export.dart` (RFC-4180 quoted; temp file →
  `share_plus`). Available on every statement screen.

---

## 7. Backup architecture

All data lives exclusively in the local SQLite database. The backup
system makes file copies of that database to user-visible storage.

### 7.1 `BackupService`

- **Output directory**:
  - Android: `<ExternalDocuments>/Bismillah_Backups/` — survives app
    uninstall on devices that preserve `Android/data/<package>/files/`.
  - Desktop / iOS fallback: `<AppDocuments>/Bismillah_Backups/`.
- **Two files written each run**:
  - `solo_con_<UTC-stamp>.db` — timestamped snapshot.
  - `solo_con_latest.db` — always overwrites; one-tap share target.
- **Atomic copy**: writes to `<dest>.tmp` then renames. A crash during
  copy leaves only an orphaned `.tmp`, never a corrupted destination
  file. Stale `.tmp` from a previous crashed run is deleted before each
  fresh copy.
- **Retention**: the last 30 timestamped snapshots are kept; older ones
  pruned automatically. The latest pointer is protected from deletion.
- `maybeRunSilentBackup()` gates on `last_backup_at` setting (≥ 6 h).
- `shareBackup()` triggers the system share sheet (WhatsApp, Gmail,
  Drive).
- `importBackup(path)` — validates the SQLite header, saves a
  `.before_import` rollback copy, then atomically overwrites the live
  DB.
- `rollbackLastImport()` — reinstates the `.before_import` file and
  preserves the now-old "current" as `.before_rollback` for forward
  rollback.

### 7.2 Auto-restore on first launch

`RestoreGateway` (in `features/common/`) runs before HomeScreen on every
cold boot. Logic:

1. Open the DB at the standard internal path.
2. If it has rows in `projects` or `journal_entries` → straight to
   HomeScreen (normal case).
3. If empty AND `solo_con_latest.db` exists in the backup folder →
   silently copy it over the internal DB, restart the provider tree, go
   to HomeScreen with the restored data.
4. If empty AND no backup exists → HomeScreen with empty data.

A static `_autoRestoreAttempted` flag survives the `restartApp()`
ProviderScope rebuild so a corrupt backup file cannot loop the spinner.

### 7.3 Validation contract

`validateBackupFile(path)` rejects:
- non-existent files
- files smaller than 100 B
- files whose first 16 bytes don't match the SQLite magic header
  (`'SQLite format 3 '`)

This is used by `importBackup` and exposed for unit tests.

---

## 8. Audit & traceability

Permissions are flat (single-operator app), so **the audit log is the
only forensic trail**.

- Every `softDeleteTransaction`, `restoreTransaction`,
  `hardDeleteTransaction`, `archiveProject`, `unarchiveProject` writes
  a row to `change_log`.
- Each row carries the install's stable `device_id` (UUID v4, generated
  on first run, stored in `app_settings`).
- Settings → **Change Log** lists every event newest-first with a CSV
  export.

---

## 9. Error reporting

Designed for the trial-week phase: framework, async and widget-build
errors are surfaced immediately, not silently swallowed.

### 9.1 `core/error_reporter.dart`

- Singleton holding the last 100 errors in
  `ValueNotifier<List<ErrorRecord>>`.
- `ErrorReporter.report(error, stack, source)` is callable from
  anywhere.
- Each report:
  - prepends an `ErrorRecord` to the in-memory ring buffer
  - pops a red SnackBar via a `GlobalKey<ScaffoldMessengerState>`
    (no BuildContext required, so async error handlers work)
  - the SnackBar has a "Details" action that opens a dialog with the
    full message and stack trace in monospace.

### 9.2 Wiring (`main.dart`)

```dart
FlutterError.onError = (details) {
  FlutterError.presentError(details);
  ErrorReporter.report(details.exceptionAsString(),
      stack: details.stack, source: 'FlutterError');
};

PlatformDispatcher.instance.onError = (error, stack) {
  ErrorReporter.report(error, stack: stack, source: 'Async');
  return true; // mark handled so the app doesn't crash
};

ErrorWidget.builder = (details) {
  ErrorReporter.report(details.exceptionAsString(),
      stack: details.stack, source: 'ErrorWidget');
  return _ErrorCard(message: details.exceptionAsString());
};
```

### 9.3 Surface in app

Settings → Audit → **Recent Errors** opens
`features/settings/recent_errors_screen.dart`:

- Lists each `ErrorRecord` with timestamp, source and first-line preview.
- ExpansionTile reveals full message + stack.
- "Copy full report" button bundles timestamp + source + message + stack
  into the clipboard for sharing via WhatsApp / email.

---

## 10. Boot sequence

1. `main.dart` — `WidgetsFlutterBinding.ensureInitialized()`, install
   `FlutterError.onError` / `PlatformDispatcher.onError` /
   `ErrorWidget.builder`, then conditionally
   `Supabase.initialize(...)` if `SupabaseConfig.configured`, then
   `runApp(...)`.
2. `app.dart` builds `MaterialApp` with `scaffoldMessengerKey:
   ErrorReporter.messengerKey` and **eagerly watches** three boot
   providers:
   - `syncServiceFutureProvider` — starts the sync service.
   - `backupBootCheckProvider` — runs the silent local backup if ≥ 6 h
     since last.
   - `commitSyncWiringProvider` — wires every successful ledger commit
     to `sync.syncNow()`.
3. `RestoreGateway.initState()` decides whether to silently restore
   from `solo_con_latest.db` or proceed straight to HomeScreen (see
   section 7.2).
4. `LocalDb.instance.open()` runs migrations to schema version 11.

---

## 11. Test infrastructure

**75 automated tests across 5 files**, all passing under `flutter test`:

| File                              | Tests | Coverage                                         |
| --------------------------------- | ----- | ------------------------------------------------ |
| `invariants_test.dart`            | 13    | Engine invariants — double-entry, reconciliation, soft delete, aging, audit, banks |
| `business_logic_test.dart`        | 31    | PoC revenue recognition (9), labour-payment smart settlement (4), budget-mismatch gate (7), burn rate active-days (4), supplier-payable balance (4), end-to-end regressions (2) |
| `backup_blackbox_test.dart`       | 19    | `validateBackupFile` (5), atomic copy (3), backup→restore round-trip (4), DB persistence (3), import rollback (2), corruption handling (2) |
| `user_journeys_blackbox_test.dart`| 10    | Full user flows from project creation to archive |
| `widget_test.dart`                | 2     | Account ID uniqueness, transaction kinds have label + blurb |

All tests use `sqflite_common_ffi` to drive a real SQLite engine
(in-memory or temp-file) — no mocks. Schema is applied via
`LocalDb.applySchemaForTests` so the production migration code is
exercised on every test run.

Run:
```bash
flutter test                                  # all tests
flutter test test/backup_blackbox_test.dart   # one file
flutter analyze --no-fatal-infos              # static analysis
```

---

## 12. Schema migration history

| Version | Changes |
| ------- | ------- |
| v1      | Initial schema: customers, suppliers, projects, journal_entries, change_log, app_settings |
| v2      | ntn_cnic / address / credit_limit on customers; category / tax_status / bank_details on suppliers; customer_id / site_address / budget / project_manager on projects; banks + counter_entities + material_inventory tables |
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

## 13. Build & run

### 13.1 Prerequisites

- Flutter SDK 3.x with Dart 3.11.5+
- Android SDK 34 (`compileSdk` pinned in `android/build.gradle.kts`)
- For desktop: Visual Studio 2022 build tools (Windows)

### 13.2 Quick start

```bash
flutter pub get
flutter run                  # connected phone / emulator
flutter run -d windows       # Windows desktop
```

### 13.3 Release builds

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

Signed APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

### 13.4 Build-output relocation (Windows + OneDrive)

If your project lives inside a OneDrive-synced folder, the Android build
can fail with a permission error. Set `BISMILLAH_BUILD_DIR` to a path
outside OneDrive before building:

```powershell
$env:BISMILLAH_BUILD_DIR = "C:\bismillah-build"
flutter build apk --release
```

`android/build.gradle.kts` honours this env var.

---

## 14. Coding conventions

- Repositories never import `package:flutter/*`. Pure Dart — easy to
  unit-test with `sqflite_common_ffi`.
- Models are plain classes with `toMap()` / `fromMap()` / `const`
  constructors. No code generation.
- Screens use `ConsumerWidget` / `ConsumerStatefulWidget`. State that
  triggers data re-fetch goes through `ledgerVersionProvider`
  (`bumpLedger(ref)` after any mutation).
- Money is stored as `REAL` (double) in SQLite and formatted via
  `fmtMoney` / `fmtSignedMoney` / `fmtCompactMoney`. PKR, no decimal
  digits in the UI.
- Times are stored as ISO-8601 UTC strings; converted to local time for
  display via `fmtDate` / `fmtDateTime`.
- Positive/negative coloring uses `BalanceColors.signed(context, value)`
  — never hard-coded `Colors.green` / `Colors.red`.
- Comments reserved for the *why* (constraints, invariants, surprising
  behavior) — never the *what*.
- Theme palette: indigo (CTAs/buttons), deep navy (AppBar), cool gray
  (light scaffold), Material-3-derived surface (dark scaffold), emerald
  (positive financial), rose (negative financial). Red/green strictly
  reserved for financial gain/loss per the design spec.

---

## 15. License

Internal — © Bismillah Constructions.
