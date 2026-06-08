# Bismillah Constructions ERP

Offline-first, double-entry construction-project ledger built in Flutter.
Designed for a single operator running multiple sites: cash, banks,
suppliers, materials, labour, project P&L — all in one place, with a
local backup that survives app uninstall on most Android devices and
optional cloud sync to Supabase for multi-device use.

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

### Operational memory

State that lives next to the money so site decisions aren't lost
between visits:

- **Notes** — pinnable free-text notes attached to a project or
  supplier; surface in their detail screens.
- **Site Snapshot** — one-screen aggregate per project: budget vs
  spent, customer deposit, supplier payables, projected remaining
  cost (driven by an owner-entered completion% slider), projected
  cash gap and projected final profit. Risk band (green/amber/red).
- **Closure Assistant** — gated walkthrough of what's still wrong
  before a project can be archived: outstanding payables, budget
  mismatch, missing service-fee reclassification for LR.
- **Follow-Ups** — recovery / billing reminders with expected date,
  priority, amount estimate; overdue tile on the dashboard.

### Dashboard

- **Treasury** — Net Liquidity, Net Position, Net Worth in one card,
  with a "Profit Illusion" insight that explains how much of your
  cash is earmarked for unpaid bills.
- **Wallets & Banks** grid — Cash plus every user-defined bank /
  wallet tile, tappable into its ledger.
- **Payables / Receivables** summary tiles.
- **Customer Deposits** tile — money received but not yet earned.
- **Projects at Risk** — projects ≥ 80% of budget, over-budget jobs
  flagged first.
- **Overdue Follow-Ups** — recovery reminders past their expected
  date.
- **Cash Runway** — traffic-light card. Burn rate averages across
  **active days only** in the last 30 days, so a single big-spend
  day yields a meaningful daily figure instead of a diluted
  1700-day artefact.
- **7-Day Spending** bar chart with peak day highlighted.
- **Recent Activity** — last few transactions, grouped by date,
  "See all" opens the full history.

### Reports

Grouped on the Reports tab so the ledgers come first (those are
reached for daily), formal statements next, then aging, operations,
and project analysis.

**Ledgers** — every ledger screen shows a **trial-balance header**
(opening / debits / credits / closing) plus a per-supplier or
per-material breakdown on the project ledger.
- Material Supplier Ledger
- Labour Supplier Ledger (Wage Register)
- Bank / Wallet Ledger
- Project Ledger (with supplier and material breakdowns)

**Financial Statements**
- Income Statement (P&L) — material-type and worker breakdowns,
  Customer Deposits info row, Loss Provision line, at-risk banner.
  CSV + PDF export.
- Balance Sheet — Net Worth model (Assets − Liabilities). No
  equity plug; cumulative recognized profit appears as a
  cross-check memo. CSV + PDF export.
- Cash Flow Statement — Operating / Financing broken down by
  category (Receipts from customers, Supplier payments, Labour,
  Counter purchases, Owner draws, internal transfers eliminated).
  12-month bar chart.
- Monthly P&L Trend — recognized income / costs / net profit per
  month over the last 12 months, computed as cumulative deltas so
  PoC recognition is properly bucketed mid-project. Line chart +
  data table + CSV export.

**Aging** — FIFO open-balance matcher, 0-30 / 31-60 / 61-90 / 90+
day buckets.
- Aging — Payables (per supplier)
- Aging — Receivables (under-funded projects + supplier overpayments)

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

### Cloud sync (optional)

Push every domain row to Supabase Postgres for cloud backup and
multi-device use.

- **Push** every local write within seconds of commit.
- **Pull** on app start and on demand; uses an `updated_at`
  cursor per table so only new rows come down.
- **INSERT-only** conflict resolution: rows that already exist
  locally are skipped, so a local write is never overwritten by
  the server. The cloud is effectively a mirror of every device's
  writes.
- **Tenant id** — one UUID per operator, set on first sync and
  copied to a second device by signing in with the same
  credentials. Two unrelated installs never see each other's data.
- **Build-time credentials** — `SUPABASE_URL` and
  `SUPABASE_ANON_KEY` are baked into the APK via `--dart-define`;
  no secrets are committed. Apply [supabase/migrations/0001_initial.sql](supabase/migrations/0001_initial.sql)
  in the Supabase SQL Editor once before first sync.

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
- **Pill navigation bar** at the bottom of Home — stadium-shaped
  capsule, active destination expands to a filled pill with the
  primary colour, inactive collapse to icon-only.
- Charts render with compact money labels (Rs 1.5L, Rs 250k) and
  auto-picked "nice" intervals.

### Settings

- Appearance (light / dark / system).
- Backup & Export — Run backup now, Share latest, Import, Undo,
  Backup history, Backup folder probe.
- Cloud Sync — connection status, last-sync timestamp, force pull,
  reset tenant.
- Audit — Change Log, Recent Errors.
- Catalogs — Material Types (with UoM, coverage rate, waste factor,
  lead time), Labour Types (with default daily rate).

### 106 automated tests

All passing under `flutter test`:

- `invariants_test.dart` — engine invariants: double-entry balance,
  reconciliation, soft delete, aging, audit, banks.
- `business_logic_test.dart` — PoC revenue recognition,
  labour-payment smart settle, budget-mismatch gate, burn-rate
  active-days, supplier-payable balance.
- `backup_blackbox_test.dart` — header validation, atomic copy,
  backup round-trip, persistence, import rollback, corruption
  handling.
- `project_breakdown_test.dart` — per-supplier and per-material
  spend roll-ups for the project ledger.
- `user_journeys_blackbox_test.dart` — full flows from project
  creation to archive.
- `widget_test.dart` — account ID uniqueness, transaction kinds
  carry label + blurb.

All tests use `sqflite_common_ffi` to drive a real SQLite engine
(no mocks); the production migration code runs on every test.

---

## Documentation

- **[USER_MANUAL.md](USER_MANUAL.md)** — for the operator. Tabs,
  transactions, project lifecycle, the dashboard, reports, backup &
  restore, cloud sync, FAQs, common scenarios.
- **[TECHNICAL.md](TECHNICAL.md)** — for engineers. Tech stack,
  architecture, data model, schema (v16), repositories, providers,
  transaction kinds, reporting engine, backup mechanics, cloud-sync
  design, error reporting, build & test instructions,
  schema-migration history.
- **[CLAUDE.md](CLAUDE.md)** — orientation notes for AI assistants
  and future maintainers: load-bearing invariants, non-obvious
  design decisions, things deliberately missing, where things live.

---

## Quick start

```bash
cd bismillah_constructions
flutter pub get
flutter run                  # connected phone / emulator
flutter run -d windows       # Windows desktop
flutter test                 # 106 automated tests
flutter analyze --no-fatal-infos
```

### Release builds

```bash
flutter build apk --release                   # universal APK
flutter build apk --release --split-per-abi   # per-ABI APKs
flutter build appbundle --release             # Play Store AAB
flutter build windows --release               # Windows desktop
```

### Release builds with cloud sync

Pass Supabase credentials at build time so they're baked into the
binary instead of committed to source:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-anon-key>
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
- Local backups are written to user-visible storage on the same
  device.
- Cloud sync is **opt-in** — only active when `SUPABASE_URL` and
  `SUPABASE_ANON_KEY` are baked into the build. Without those, the
  app runs fully offline and no data leaves the device.
- No analytics, no telemetry, no crash-reporting service.

---

## License

Internal — © Bismillah Constructions.
