import 'package:flutter/material.dart';

import 'aging_analysis_screen.dart';
import 'aging_receivables_screen.dart';
import 'balance_sheet_screen.dart';
import 'bank_ledger_screen.dart';
import 'cash_flow_screen.dart';
import 'income_statement_screen.dart';
import 'project_bva_picker_screen.dart';
import 'project_ledger_screen.dart';
import 'project_profitability_screen.dart';
import 'supplier_ledger_picker_screen.dart';
import 'supplier_spending_screen.dart';
import 'wage_ledger_screen.dart';

/// Reports landing page. Tiles are grouped into four sections so the
/// list stays scannable as more reports get added:
///   * **Financial Statements** — the big-three numbers a small business
///     looks at first (P&L, Balance Sheet, Cash Flow).
///   * **Ledgers** — per-party / per-account statements of activity.
///   * **Aging** — what's owed and how stale it is.
///   * **Project** — project-specific reports (currently just BvA).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionTitle('Financial Statements'),
          _ReportTile(
            icon: Icons.trending_up,
            color: Colors.green,
            title: 'Income Statement (P&L)',
            subtitle: 'Revenue minus material and labour costs',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const IncomeStatementScreen())),
          ),
          _ReportTile(
            icon: Icons.account_balance,
            color: Colors.blue,
            title: 'Balance Sheet',
            subtitle: 'Assets vs Liabilities + Equity',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BalanceSheetScreen())),
          ),
          _ReportTile(
            icon: Icons.swap_vert,
            color: Colors.deepPurple,
            title: 'Cash Flow Statement',
            subtitle:
                'Operating, financing and net cash movement across all projects',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CashFlowScreen())),
          ),
          _SectionTitle('Ledgers'),
          _ReportTile(
            icon: Icons.receipt_long,
            color: Colors.teal,
            title: 'Material Supplier Ledger',
            subtitle:
                'Statement of account for a material supplier (across or within a project)',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupplierLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.engineering,
            color: Colors.purple,
            title: 'Labour Supplier Ledger',
            subtitle:
                'Per-worker statement of every wage charged (paid + on credit), date-filterable',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WageLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.account_balance_wallet,
            color: Colors.cyan,
            title: 'Bank / Wallet Ledger',
            subtitle:
                'Statement of every transaction through a specific bank or wallet',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BankLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.foundation,
            color: Colors.indigo,
            title: 'Project Ledger',
            subtitle: 'All transactions for a single project (running balance)',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProjectLedgerPickerScreen())),
          ),
          _SectionTitle('Aging'),
          _ReportTile(
            icon: Icons.hourglass_bottom,
            color: Colors.red,
            title: 'Aging — Payables',
            subtitle:
                'Outstanding supplier payables bucketed 0-30 / 31-60 / 61-90 / 90+',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AgingAnalysisScreen())),
          ),
          _ReportTile(
            icon: Icons.hourglass_top,
            color: Colors.amber,
            title: 'Aging — Receivables',
            subtitle:
                'Money owed to you — projects under-funded by customers, suppliers we\'ve overpaid',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AgingReceivablesScreen())),
          ),
          _SectionTitle('Operations'),
          _ReportTile(
            icon: Icons.bar_chart,
            color: Colors.deepOrange,
            title: 'Supplier-wise Spending',
            subtitle:
                'Which vendors consume the most capital — material + labour combined, filterable by period',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupplierSpendingScreen())),
          ),
          _SectionTitle('Project Analysis'),
          _ReportTile(
            icon: Icons.assessment,
            color: Colors.pink,
            title: 'Budget vs Actual',
            subtitle: 'Project budget vs actual spend, by category',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProjectBvaPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.leaderboard,
            color: Colors.brown,
            title: 'Project Profitability',
            subtitle:
                'Per-project Received vs Spent vs Net, ranked by bottom-line return',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProjectProfitabilityScreen())),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
