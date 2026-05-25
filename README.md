# Bismillah Constructions ERP

Offline-first, double-entry construction-project ledger built in Flutter.
Designed for a single operator running multiple sites: cash, banks,
suppliers, materials, labour, project P&L — all in one place, with a
local backup that survives app uninstall on most Android devices.

---

## What this app does

Bismillah records every rupee that moves through a construction
business and turns those entries into the reports an owner-operator
actually uses day-to-day.

### Two contract models

Pick one per project — the choice changes how revenue and profit are
recognized.

- **With Material** — you buy the materials and pay labour, customer
  pays a fixed contract price. Profit = received − costs.
- **Labour Rate** — you handle labour only and earn a fixed % service
  fee on the work. Customer money is pass-through; service fee is the
  only revenue.

### Nine canonical transaction kinds

Every entry is a balanced double-entry pair. The Transaction Picker
exposes:

1. **Material Buy (Credit)** — supplier credit purchase.
2. **Material Buy (Counter Purchase)** — cash buy at a shop with no
   supplier credit relationship.
3. **Labour Payment** — smart-settle: if the worker has an outstanding
   wage credit, the payment clears it first instead of double-booking
   the cost.
4. **Labour on Credit** — wages incurred, not yet paid.
5. **Supplier Payment** — settle an outstanding payable.
6. **Receive from Project** — money in from the customer.
7. **Wallet Transfer** — move between your own cash / bank accounts.
8. **Personal / Owner Draw** — non-construction outflow.
9. **Service Fee Logged** — earn the % fee (LR projects only).

Material purchases always require a **quantity** — this powers the
Material Price Trend report.

### Percentage-of-Completion revenue recognition

Customer prepayments don't inflate profit. While a With-Material
project is in progress, revenue is recognized only up to costs
incurred (`min(received, costs)`); the rest sits as a customer-deposit
liability. Real profit appears at close. For Labour-Rate projects,
the service fee is the only earned revenue — everything else is
pass-through.

### Loss provision (FASB / IFRS)

The moment a project's costs exceed its budget, the overrun is booked
immediately as a separate cost line on the Income Statement — even if
the project hasn't closed yet. No hiding losses until reconciliation.

### Asymmetric archive gates

- **With-Material** projects need all supplier payables cleared, and
  an informational dialog opens if customer-received is below budget
  so you can decide whether to record the missing payment or edit the
  budget down.
- **Labour-Rate** projects need their pass-through ledger to net to
  zero after service-fee reclassification — refund or collect the
  residual before archiving.

### Dashboard

- **Treasury** — Net Liquidity, Net Position, Net Worth in one card,
  with a "Profit Illusion" insight that explains how much of your
  cash is earmarked for unpaid bills.
- **Wallets & Banks** grid — Cash plus every user-defined bank /
  wallet tile, tappable into its ledger.
- **Payables / Receivables** summary tiles.
- **Projects at Risk** — projects ≥ 80% of budget, over-budget jobs
  flagged first.
- **Customer Deposits** — money received but not yet earned.
- **Cash Runway** — traffic-light card. Burn rate averages across
  **active days only** in the last 30 days, so a single big-spend
  day yields a meaningful daily figure instead of a diluted
  1700-day artefact.
- **7-Day Spending** bar chart with peak day highlighted.
- **Recent Activity** — last 8 transactions, grouped by date,
  "See all" opens the full history.

### Thirteen reports

Grouped on the Reports tab so the ledgers come first (those are
reached for daily), formal statements next, then aging, operations,
and project analysis.

**Ledgers**
- Material Supplier Ledger
- Labour Supplier Ledger (Wage Register)
- Bank / Wallet Ledger
- Project Ledger

**Financial Statements**
- Income Statement (P&L) — with material-type and worker breakdowns,
  Customer Deposits info row, Loss Provision line, at-risk banner.
  CSV + PDF export.
- Balance Sheet — Assets vs Liabilities + Equity, balanced indicator.
- Cash Flow Statement — Operating / Financing broken down by
  category (Receipts from customers, Supplier payments, Labour,
  Counter purchases, Owner draws, internal transfers eliminated).
  12-month bar chart.

**Aging** — FIFO open-balance matcher per party, 0-30 / 31-60 /
61-90 / 90+ day buckets.
- Aging — Payables
- Aging — Receivables (FIFO carry-forward of customer prepayments)

**Operations**
- Supplier-wise Spending — horizontal-bar ranking, All Time / 90d /
  30d filter.

**Project Analysis**
- Budget vs Actual — summary card, budget-allocation pie,
  material-breakdown pie, spending-over-time bar with Day / Week /
  Month toggle, category table.
- Project Profitability — every project ranked by net profit; bar
  chart with green above zero, red below, bold zero line.
- Material Price Trend — pick a material type, see your
  rupee-per-unit prices over time across suppliers. Spot rising
  prices early.

### Local backup that survives uninstall

- **Automatic** on cold boot every 6 hours, written silently.
- **Atomic file copy** — `<dest>.tmp` first, then rename. A crash
  during copy can never corrupt the destination.
- **Retention** — last 30 timestamped snapshots, plus a
  `solo_con_latest.db` pointer that's always current.
- **Location** — Android external Documents folder, preserved on
  uninstall on most OEMs (some Xiaomi / Samsung One UI 6+ / strict
  Android 14+ wipe it; share off-device first in those cases).
- **Manual**: Run backup now, Share latest backup (system share
  sheet → WhatsApp / Gmail / Drive), Import backup with a SQLite
  header check, Undo last import, Backup history browser, folder
  write-access probe.
- **Auto-restore** on reinstall: if the app finds itself empty and
  `solo_con_latest.db` is in the backup folder, it silently copies
  it back and opens to Home with all your data.

### Audit & error reporting

- **Change Log** — every soft-delete, restore, archive, unarchive
  and edit recorded with timestamps, original/new JSON, the user
  note and a stable per-install device id. CSV export.
- **Recent Errors** — in-app log of every framework, async or
  widget-build error caught during the session. Each entry has
  source / timestamp / message / stack trace and a one-tap
  "Copy full report" for forwarding via WhatsApp.

### Theme & UI

- **Light, Dark, System** modes (Indigo accent, Navy AppBar).
- Positive financial values in emerald, negative in rose — never
  hard-coded; goes through `BalanceColors.signed()`.
- Frosted bottom-tab nav with tap and swipe navigation, a 4-tab
  back-stack memory.
- Charts render with compact money labels (Rs 1.5L, Rs 250k) and
  auto-picked "nice" intervals.

### Settings

- Appearance (light / dark / system).
- Backup & Export — Run backup now, Share latest, Import, Undo,
  Backup history, Backup folder probe.
- Audit — Change Log, Recent Errors.
- Catalogs — Material Types (with UoM, coverage rate, waste factor,
  lead time), Labour Types (with default daily rate).

### 75 automated tests

Across 5 files, all passing under `flutter test`:

- `invariants_test.dart` (13) — engine invariants: double-entry
  balance, reconciliation, soft delete, aging, audit, banks.
- `business_logic_test.dart` (31) — PoC revenue recognition,
  labour-payment smart settle, budget-mismatch gate, burn-rate
  active-days, supplier-payable balance, end-to-end regressions.
- `backup_blackbox_test.dart` (19) — header validation, atomic
  copy, backup round-trip, persistence, import rollback,
  corruption handling.
- `user_journeys_blackbox_test.dart` (10) — full flows from
  project creation to archive.
- `widget_test.dart` (2) — account ID uniqueness, transaction kinds
  carry label + blurb.

All tests use `sqflite_common_ffi` to drive a real SQLite engine
(no mocks); the production migration code runs on every test.

---

## Documentation

The documentation is split into three focused files:

- **[USER_MANUAL.md](USER_MANUAL.md)** — for the operator. Tabs,
  transactions, project lifecycle, the dashboard, reports, backup &
  restore, FAQs, common scenarios.
- **[TECHNICAL.md](TECHNICAL.md)** — for engineers. Tech stack,
  architecture, data model, schema (v11), repositories, providers,
  transaction kinds, reporting engine, backup mechanics, error
  reporting, build & test instructions, schema-migration history.
- **[CLAUDE.md](CLAUDE.md)** *(when present)* — orientation notes
  for AI assistants and future maintainers.

---

## Quick start

```bash
cd bismillah_constructions
flutter pub get
flutter run                  # connected phone / emulator
flutter run -d windows       # Windows desktop
flutter test                 # 75 automated tests
flutter analyze --no-fatal-infos
```

### Release builds

```bash
flutter build apk --release                   # universal APK
flutter build apk --release --split-per-abi   # per-ABI APKs
flutter build appbundle --release             # Play Store AAB
flutter build windows --release               # Windows desktop
```

If your project lives inside a OneDrive-synced folder and the Android
build fails with a permission error, redirect the build output:

```powershell
$env:BISMILLAH_BUILD_DIR = "C:\bismillah-build"
flutter build apk --release
```

For full deployment details, see
[TECHNICAL.md §13 Build & run](TECHNICAL.md#13-build--run).

---

## Privacy

- All data is stored locally on the device.
- Backups are written to user-visible storage on the same device.
- No data leaves the device unless you explicitly use Share Latest
  Backup (WhatsApp / Gmail / Drive).
- No analytics, no telemetry, no crash-reporting service.

---

## License

Internal — © Bismillah Constructions.
