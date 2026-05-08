# Bismillah Constructions ERP — User Manual

A practical guide to running your construction business through the
app, written for the owner/operator. For engineering details, see
[TECHNICAL.md](TECHNICAL.md).

---

## 1. What this app is for

Bismillah is an offline accounting and project-management app for a
construction business that runs multiple sites. It records every rupee
that moves — money received from clients, material purchases, labour
payments, supplier settlements, owner draws — and turns those entries
into reports you can use to know:

- How much cash you actually have right now.
- Whether each project is making or losing money.
- Who you owe and who owes you.
- Where your money is being spent.

It's offline-first: your data lives on the phone and is automatically
backed up to a folder that survives uninstall on most Android devices.

---

## 2. The two project models

When you create a project you choose one of two contract models. The
choice changes how revenue and profit are calculated.

### 2.1 With Material

You buy the materials and pay labour. The customer pays a fixed
contract price (the "budget"). Profit is the gap between what the
customer pays and what you spend.

- Use this model when you're handling the materials yourself.
- Revenue is recognized as you incur costs (more on this in §6).
- If the customer pays more than the contract value, the excess is
  shown as a deposit owed back.

### 2.2 Labour-Rate

You only handle labour and earn a fixed percentage fee on the work.
The customer's money funds all the spend; you're effectively a
pass-through with a service fee.

- Use this model when the customer pays for materials directly and
  you charge a % service fee on the total.
- Revenue is the service fee only.
- The residual customer money sits as a deposit that has to be
  refunded on close.

---

## 3. First launch

### 3.1 Fresh install

On first launch you'll see an empty home screen with all numbers
showing zero. Start by:

1. **Manage tab → Projects → New Project** — create your first project.
2. **Manage tab → Suppliers → New Supplier** — add the vendors you
   buy from.
3. **Manage tab → Wallets & Banks → New Bank** — add HBL, Meezan,
   Easypaisa, Cash safes etc. (Cash and Supervisor Float are pre-built.)
4. **Manage tab → Material Types** — define the categories you'll buy
   under (Cement, Brick, Sand, custom).
5. **Manage tab → Labour Types** — define the worker categories (Mason,
   Electrician, Plumber, etc.).

Once these are set up you can start posting transactions.

### 3.2 Reinstall on the same phone

If you previously used the app on the same phone and uninstalled it:

- The app starts up, finds the existing `solo_con_latest.db` in the
  Bismillah_Backups folder, and **silently restores it** — no dialog,
  no prompts, no spinner.
- You arrive on the home screen with all your data intact.

If the backup folder was wiped by Android during uninstall, the app
opens empty. In that case use **Settings → Import backup** to pick a
saved `.db` file from Downloads / WhatsApp / a USB drive.

---

## 4. Navigating the app

### 4.1 Bottom tabs

Four tabs, in this order:

1. **Home** — the dashboard. Treasury, recent activity, daily spend,
   loss warnings.
2. **Manage** — entities: Projects, Suppliers, Wallets & Banks,
   Material Types, Labour Types.
3. **Reports** — every financial statement and chart.
4. **Settings** — appearance, backup, audit log, types catalogs,
   recent errors.

### 4.2 Switching tabs

- **Tap** a tab icon at the bottom — smooth slide animation, even
  across non-adjacent tabs (Home → Settings doesn't flash through
  Manage and Reports).
- **Swipe left/right** anywhere on the page — moves to the adjacent
  tab. Swiping inside a sub-screen (e.g. inside Income Statement) is
  inert — only the top-level tabs are swipeable.

### 4.3 Back button

The app remembers up to **4 tabs of history**. Pressing back walks
back through the tabs you visited:

> Example: Home → Settings → Manage → Home → Reports → Settings →
> Manage. Press back four times: Settings → Reports → Home → exit.

If you're inside a sub-screen (e.g. you tapped a tile in Reports),
back returns to that tab's landing page first; pressing back again
walks the tab history.

---

## 5. Recording transactions

The big floating **+** button at the bottom-right of the dashboard
opens the Transaction Picker. Each kind posts a balanced
double-entry pair so the books stay correct.

### 5.1 Material Buy (Credit)

You bought material from a supplier on credit (you'll pay later).

- **Effect**: Material Costs go up; the supplier's balance goes up
  (you owe them).
- **Required**: project, supplier, amount.
- **Use this** every time you take delivery of material whether or
  not you've paid yet.

### 5.2 Labour Payment

You paid a worker for labour.

- **Effect**: depends on whether the worker has unpaid wages on
  credit:
  - Worker has nothing owed → posts as a fresh Labour Cost.
  - Worker is owed `X`, you pay ≤ `X` → settles the existing
    payable, **no new cost line** (the cost was booked at credit
    time).
  - Worker is owed `X`, you pay > `X` → settles the `X` and books
    the excess as a fresh Labour Cost.
- **Required**: project, worker (supplier), amount, paid-from
  account.
- **This is the smart-settle behavior**: it fixes the bug where
  paying a worker after recording credit would double-count the
  cost.

### 5.3 Labour on Credit

Wages incurred but not yet paid. Common when you record a day's wages
in the evening but pay weekly.

- **Effect**: Labour Costs go up; the worker's balance goes up.
- **Required**: project, worker (supplier), amount.

### 5.4 Supplier / Worker Payment

A direct payment to settle an outstanding payable (material or
labour).

- **Effect**: the supplier's balance goes down; cash/bank goes down.
- **Required**: supplier, paid-from account, amount.

### 5.5 Receive from Project

Money received from the client.

- **Effect**: cash/bank goes up; Project Revenue goes up.
- **Required**: project, received-into account, amount.
- The dashboard immediately shows this money as a **Customer Deposit**
  (orange card) until you incur matching costs — this is intentional,
  see §6.

### 5.6 Wallet Transfer

Move money between your own accounts (Cash → Bank, Bank → Supervisor
Float, etc.).

- **Effect**: source goes down by the amount, destination goes up.
- **Required**: source ≠ destination, both cash-like.

### 5.7 Personal / Owner Draw

You took money for personal use (not project-related).

- **Effect**: cash/bank goes down; Personal Draw expense goes up.
- **Required**: paid-from account, amount.

### 5.8 Service Fee Logged

You collected a service fee (Labour-Rate model only).

- **Effect**: cash/bank goes up; Service Fee Income goes up.
- **Required**: project, received-into account, amount.

---

## 6. Project lifecycle

### 6.1 Create

**Manage → Projects → New Project**. Fill:

- Name (required)
- Model: With Material or Labour Rate (required)
- Client name (optional, free-text)
- Site address (optional)
- **Budget**: for With-Material, this is the contract price (what the
  customer agrees to pay). For Labour-Rate, it's a planning ceiling.
- Project manager (optional)
- Service fee % (Labour-Rate only)

### 6.2 Spend & receive (active phase)

Throughout the project life, post transactions as they happen. The
dashboard's Treasury card stays accurate without any extra effort:

- **Net Profit** is **0** while the project is in progress. This is
  intentional — until you actually deliver work, the customer's money
  is a liability (deposit), not earned profit. As you incur costs,
  matching revenue gets recognized so net profit stays at zero
  (cost-recovery PoC). Real profit appears at close.
- **Customer Deposits** card on the dashboard tells you how much
  money you've received that hasn't been earned yet — money you'd
  owe back if the project were cancelled.

### 6.3 Loss warnings

If a project's costs approach or exceed its budget you'll see:

- **Budget vs Actual** screen: the summary card turns red, the
  progress bar fills past 100%, and an "Over Budget" line shows the
  overrun.
- **Income Statement**: an at-risk banner appears at the top listing
  every project ≥ 80% of budget, with over-budget jobs flagged in red.
- **Dashboard**: a "Projects at Risk" card appears under Treasury
  showing the worst offenders.
- **Loss Provision**: when a project's costs exceed budget, the
  excess is immediately recognized as a separate cost line in the
  Income Statement — even if the project isn't closed yet. This
  follows GAAP/IFRS rules: future losses must be booked the moment
  they become probable.

### 6.4 Closing a project (Archive)

When the work is done, **Project → Reconcile & Archive → Archive**.
What happens depends on the numbers:

- **Clean close**: all suppliers settled, received = budget → project
  archives immediately. Net profit = received − costs.
- **Customer paid less than budget** (received < budget): a dialog
  opens showing:
  - Original budget
  - Total received
  - Shortfall (in red)
  - Two buttons: **"Set budget to Rs X"** (resize the contract to
    match what was actually received and archive) or **Cancel** (go
    back and either record the remaining payment or leave the
    project open).
- **Customer overpaid** (received > budget): archives without a
  dialog. The dashboard's Customer Deposits card shows the excess
  amount as money you'd refund.
- **Suppliers still owed money**: archive is blocked with a
  SnackBar — pay them first.
- **Labour-Rate project**: the budget gate is skipped. LR projects
  have their own close summary (refund / collect) on the
  reconciliation screen.

### 6.5 Unarchive

Mistakes happen. **Project tile → Unarchive** moves a closed project
back to active. All historical data is preserved.

---

## 7. The dashboard explained

Each card on the home screen, top to bottom:

### 7.1 Treasury Overview (purple card)

Three derived numbers in one row:

- **Net Liquidity** = liquid cash − supplier payables. This is the
  cash you actually have *after* paying everyone you owe.
- **Net Position** = counter receivables − (payables + counter
  payables). External assets minus liabilities outside the books.
- **Net Worth** = liquid cash + net position. Total of everything
  the business has.

Below the divider, a **Profit Illusion insight**: if your liquid
cash is greater than your real profit, it explains how much of that
cash is actually earmarked for unpaid bills.

### 7.2 Wallets & Banks

A grid of tiles — one for Cash, one for each bank/wallet you defined
in Manage. Tap a bank tile to open its ledger. The Cash tile is a
display-only summary. Together these add up to **Liquid Cash**.

### 7.3 Payables / Receivables

Two summary tiles: total money owed to suppliers (red) and total
money owed to you (green).

### 7.4 Projects at Risk (only when applicable)

Yellow / red banner listing the up to 4 projects where costs ≥ 80%
of budget. Over-budget projects appear first in red; approaching-
budget ones in orange.

### 7.5 Customer Deposits (only when applicable)

Orange banner showing total money received from customers that
hasn't been earned yet through cost-incurred work. This is a
liability — you'd refund it if the work were cancelled.

### 7.6 Cash Runway

A traffic-light card showing how many days of cash you have left at
your current burn rate:

- **Green** (≥ 30 days): healthy.
- **Yellow** (15–30 days): caution.
- **Red** (< 15 days): critical, act now.

The burn rate is the average daily spend across **active days only**
in the last 30 days (days where you actually spent money). This way a
single big spend day yields a meaningful daily figure immediately —
not diluted to near-zero by 29 idle days.

### 7.7 7-Day Spending

A bar chart showing material + labour costs for the last 7 days. The
peak day is highlighted in the tertiary accent color.

### 7.8 Recent Activity

The last 8 transactions, grouped by date. The "See all" button opens
the full transaction history with date headers.

---

## 8. Reports

The Reports tab groups all financial statements into four sections.

### 8.1 Financial Statements

- **Income Statement (P&L)** — Revenue, costs, net profit. Honors the
  PoC revenue-recognition model: customer payments don't count as
  revenue until matching costs are incurred. Includes a Customer
  Deposits informational section, a Loss Provision line when any
  project is over budget, and an at-risk banner. CSV + PDF export.
- **Balance Sheet** — Assets vs Liabilities + Equity, with a
  balanced/unbalanced indicator.
- **Cash Flow Statement** — Operating, financing and net cash
  movement across all projects. 12-month bar chart.

### 8.2 Ledgers

- **Material Supplier Ledger** — every transaction with a single
  material supplier; running balance.
- **Labour Supplier Ledger (Wage Register)** — per-worker statement
  of every wage charged (paid + on credit), date-filterable.
- **Bank / Wallet Ledger** — every transaction through a specific
  bank or wallet account.
- **Project Ledger** — every transaction for a single project; running
  balance.

### 8.3 Aging

- **Aging — Payables** — outstanding supplier payables bucketed
  0–30 / 31–60 / 61–90 / 90+ days.
- **Aging — Receivables** — money owed to you (project under-funding
  + supplier overpayments).

### 8.4 Operations

- **Supplier-wise Spending** — horizontal-bar breakdown of every
  supplier ranked by total spend (material + labour combined).
  Filter: All Time / 90 days / 30 days.

### 8.5 Project Analysis

- **Budget vs Actual (BvA)** — pick a project and see:
  - Summary card with budget / actual / remaining and a progress bar.
  - **Budget Allocation pie**: orange (material) / blue (labour) /
    green (remaining).
  - **Material Breakdown pie**: spend split by material type.
  - **Spending Over Time bar**: Day / Week / Month toggle. Y-axis
    labelled with compact money (Rs 1.5L, Rs 250k); tap a bar for the
    exact amount.
  - Category data table.
- **Project Profitability** — every project ranked by net profit.
  Per-project bar chart with green above zero (profit) and red below
  (loss), bold zero line.

---

## 9. Backup & Restore

This is the area to understand best — your data depends on it.

### 9.1 Where backups live

On Android: `Android/data/com.bismillah_constructions/files/Documents/Bismillah_Backups/`

On most devices this folder is preserved when you uninstall the app
("don't delete app data" is the default behavior). Some newer
Android versions and OEMs (Xiaomi, Samsung One UI 6+, Android 14+
strict mode) wipe this folder on uninstall regardless. If that
happens on your device, you'll need to share the backup file off-
device first (see §9.5).

The folder contains:

- `solo_con_<timestamp>.db` — historical snapshots, up to 30 retained.
- `solo_con_latest.db` — always overwrites, the one used for sharing
  and auto-restore.

### 9.2 Automatic backups

- **Cold-boot trigger**: every time you launch the app, if the last
  backup is older than 6 hours, a fresh backup is written silently.
- **Atomic copy**: the file is written to `<dest>.tmp` first, then
  renamed. If the app crashes during the copy, you're left with a
  stray `.tmp` and an intact previous backup — never a corrupted
  destination.
- **Retention**: the last 30 timestamped snapshots are kept; older
  ones are pruned automatically. The latest pointer is protected
  from deletion.

### 9.3 Manual backup

**Settings → Backup & Export → Run backup now**. Writes a fresh
snapshot regardless of how recent the last one was.

### 9.4 Verify backup folder access

**Settings → Backup folder → bug-report icon**. Writes a tiny probe
file to the folder and deletes it. SnackBar confirms write
permission. Use this if you suspect storage permission issues.

### 9.5 Sharing a backup off-device

**Settings → Share latest backup**. Opens the system share sheet —
pick WhatsApp, Gmail, Drive, or any installed share target. The
backup file (`solo_con_latest.db`) is sent as an attachment. Save it
somewhere safe.

### 9.6 Importing a backup

**Settings → Import backup → pick `.db` file**. The app:

1. Validates the SQLite header — rejects non-database files
   (e.g. text files renamed to `.db`) with a clear message.
2. Saves the current DB as `solo_con.before_import` — your safety
   net.
3. Atomically replaces the live DB with the imported file.
4. Shows "Restart the app to load the new database."

After the restart your data matches the imported backup. The
pre-import data is preserved in `solo_con.before_import`.

### 9.7 Undo last import

If the imported backup wasn't what you wanted: **Settings → Undo
last import**. This:

1. Saves the current (imported) DB as `solo_con.before_rollback`
   — in case you want to undo the undo.
2. Copies `solo_con.before_import` back into place.
3. Asks you to restart.

After restart the pre-import data is back.

### 9.8 Auto-restore on reinstall

If you uninstall and reinstall the app on the same device, the
backup folder is the bridge. On first launch after reinstall:

- App opens its (empty) database.
- Detects the empty state.
- Looks for `solo_con_latest.db` in `Bismillah_Backups/`.
- If found → silently copies it over, restarts the providers, opens
  Home with all your data.
- If not found → opens empty (no dialog, no prompt).

A guard flag prevents the restore from looping if the backup file is
corrupt — at most one auto-restore attempt per launch.

### 9.9 Backup history

**Settings → Backup history**. Shows every backup file in the
folder with size and modified date. Tap a file to:

- Share it (off-device save)
- Import it (replace current DB)
- Delete it (the latest pointer is protected)

---

## 10. Settings

### 10.1 Appearance

- **System default** — follows the device dark-mode toggle.
- **Light** — Indigo theme on a cool gray background.
- **Dark** — Indigo theme on a soft indigo-tinted dark background
  (not pitch black — easier on the eyes).

In both themes, the AppBar is deep navy. Buttons are indigo.
Positive financial values are emerald, negative are rose.

### 10.2 Backup & Export

Run backup now, view history, share, import, undo, test folder
permissions, copy folder path. All explained in §9.

### 10.3 Audit

- **Change Log** — every soft-delete, archive, and edit recorded
  with timestamps, original/new values, the user note, and the
  device id. CSV export available.
- **Recent Errors** — in-app log of every framework, async, or
  widget-build error caught during the current session. Each entry
  has the timestamp, source label, full message, and stack trace.
  Long-press / tap to expand; "Copy full report" sends the whole
  thing to your clipboard for forwarding via WhatsApp. Cleared on
  cold start (in-memory only).

### 10.4 Catalogs

- **Material Types** — add / edit / delete categories that appear in
  the Material Buy form (Brick, Cement, Sand, custom). Procurement
  metadata: unit of measure, coverage rate, waste factor, lead time.
- **Labour Types** — add / edit / delete worker categories (Mason,
  Electrician, Plumber, etc.) with optional default daily rate.

---

## 11. Common scenarios

### 11.1 "I bought material on credit and need to pay later"

1. + → **Material Buy (Credit)** → fill project, supplier, amount.
2. Later, when paying: + → **Supplier / Worker Payment** → pick the
   same supplier, paid-from account, amount.

The supplier balance goes up at step 1 and down at step 2.

### 11.2 "I paid a daily wage today"

1. + → **Labour Payment** → fill project, worker, paid-from, amount.

Single transaction. No credit phase needed.

### 11.3 "I recorded weekly wages but pay on Saturday"

1. Each work day: + → **Labour on Credit** → project, worker,
   amount. Builds up the worker's balance.
2. Saturday: + → **Labour Payment** (or **Supplier / Worker
   Payment**) → same worker, total amount.

The Labour Payment route is smart — it'll settle the existing credit
first and only book a new cost if you pay more than is owed.

### 11.4 "Customer paid an advance before any work started"

1. + → **Receive from Project** → project, account, amount.
2. The dashboard shows it as a **Customer Deposit** (owed back) — not
   profit.
3. As you incur costs, the deposit liability shrinks and revenue is
   recognized to match.

### 11.5 "I need to send last month's books to my accountant"

1. **Reports → Income Statement** → date range: last month → CSV
   button → share via WhatsApp / email.
2. **Reports → Balance Sheet** → CSV.
3. **Reports → Project Profitability** → CSV.
4. **Settings → Change Log** → CSV (audit trail).

### 11.6 "Switching to a new phone"

1. On the old phone: **Settings → Share latest backup** → send to
   yourself via WhatsApp / Gmail.
2. On the new phone: install the APK.
3. Save the received `.db` file to Downloads.
4. **Settings → Import backup** → pick the file.
5. Restart the app.

All your data is on the new phone.

### 11.7 "The app crashed / something is wrong"

1. **Settings → Audit → Recent Errors**.
2. Find the entry, tap to expand, tap **Copy full report**.
3. Paste into WhatsApp / email and forward.

---

## 12. FAQ / troubleshooting

**Q: My Net Profit shows zero even though I received money. Why?**

That's intentional. Until you actually incur costs to deliver the
work, the customer's money is a deposit (liability), not earned
revenue. As you spend on materials and labour, the matching revenue
gets recognized. Real profit shows up when the project is closed.

**Q: The Income Statement shows a "Loss Provision" line. What is
that?**

If any project's costs have exceeded its budget, the overrun is
booked as an immediate cost — even if the project isn't closed.
This follows GAAP/IFRS rules: don't hide a loss until close. Open
that project's BvA report to see the overrun amount.

**Q: I can't archive a project. Why?**

Two possible reasons:

1. **Suppliers still owed money** — the SnackBar will say "Archive
   blocked — Rs X of supplier payables still open." Settle them
   first.
2. **Customer paid less than budget** (With-Material only) — a
   dialog appears asking you to either resize the budget to match
   what was received, or cancel and record the remaining payment
   first.

**Q: My Cash Runway shows 1700 days. Is that real?**

It depends on how much spending data you have. Cash Runway = liquid
cash ÷ average daily burn. The burn is averaged across the days you
actually spent money in the last 30 days. If you've only spent on
one day, that single day's spend is your "average". Once you have a
few weeks of regular activity, the number becomes meaningful.

**Q: I uninstalled the app and now my data is gone.**

If your device wipes `Android/data/<package>/` on uninstall (some
Xiaomi, Samsung One UI 6+, and stricter Android 14+ devices do this),
the backup folder went with it. Going forward: always **Settings →
Share latest backup** to send a copy off-device before uninstalling.

**Q: I imported a backup and now things look wrong.**

**Settings → Undo last import**. Restart the app. Your pre-import
data comes back.

**Q: I see Recent Errors entries — should I worry?**

The trial week's purpose is to catch these. Open the entry, tap
"Copy full report", and forward it for fixing. The app keeps running
even when errors are caught — none of these crash the app.

---

## 13. Keyboard shortcuts (desktop)

Desktop builds inherit Flutter's standard navigation:
`Ctrl+W` closes the window, `Ctrl+R` (in dev) hot-reloads. There are
no custom shortcuts at this stage.

---

## 14. Privacy

- All data is stored locally on the device.
- Backups are written to user-visible storage on the same device.
- No data is sent off-device unless you explicitly use the Share
  Backup feature (WhatsApp, Gmail, Drive).
- No analytics, no telemetry, no crash reporting service.

---

## 15. Getting help

For bug reports during the trial week:

1. **Settings → Recent Errors** → copy the relevant report.
2. Note your Android version + phone model.
3. If the issue is data-shaped: **Settings → Share latest backup**
   so the data state can be inspected.
4. Send all of the above via WhatsApp.

---

© Bismillah Constructions. Internal use.
