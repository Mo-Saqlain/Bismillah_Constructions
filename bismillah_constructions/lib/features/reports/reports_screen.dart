import 'package:flutter/material.dart';

import 'aging_analysis_screen.dart';
import 'balance_sheet_screen.dart';
import 'cash_flow_screen.dart';
import 'income_statement_screen.dart';
import 'project_bva_picker_screen.dart';
import 'project_ledger_screen.dart';
import 'supplier_ledger_picker_screen.dart';
import 'wage_ledger_screen.dart';
import 'bank_ledger_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ReportTile(
            icon: Icons.trending_up,
            title: 'Income Statement (P&L)',
            subtitle: 'Revenue minus material and labour costs',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const IncomeStatementScreen())),
          ),
          _ReportTile(
            icon: Icons.account_balance,
            title: 'Balance Sheet',
            subtitle: 'Assets vs Liabilities + Equity',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BalanceSheetScreen())),
          ),
          _ReportTile(
            icon: Icons.assessment,
            title: 'Budget vs Actual',
            subtitle: 'Project budget vs actual spend, by category',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProjectBvaPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.engineering,
            title: 'Wage Ledger',
            subtitle:
                'Per-worker statement of every wage charged (paid + on credit), date-filterable',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WageLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.swap_vert,
            title: 'Cash Flow Statement',
            subtitle:
                'Operating, financing and net cash movement across all projects',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CashFlowScreen())),
          ),
          _ReportTile(
            icon: Icons.receipt_long,
            title: 'Supplier Ledger',
            subtitle:
                'Statement of account for a supplier (across or within a project)',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupplierLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.account_balance_wallet,
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
            title: 'Project Ledger',
            subtitle: 'All transactions for a single project (running balance)',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProjectLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.hourglass_bottom,
            title: 'Aging — Payables',
            subtitle:
                'Outstanding supplier payables bucketed 0-30 / 31-60 / 61-90 / 90+',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AgingAnalysisScreen())),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
