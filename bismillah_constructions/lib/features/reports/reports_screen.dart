import 'package:flutter/material.dart';

import 'balance_sheet_screen.dart';
import 'customer_ledger_screen.dart';
import 'income_statement_screen.dart';
import 'supplier_ledger_picker_screen.dart';

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
            subtitle: 'Assets vs Liabilities + Equity (with balance check)',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BalanceSheetScreen())),
          ),
          _ReportTile(
            icon: Icons.receipt_long,
            title: 'Supplier Ledger',
            subtitle: 'Statement of account for a supplier (filter by project)',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupplierLedgerPickerScreen())),
          ),
          _ReportTile(
            icon: Icons.person_search,
            title: 'Customer Ledger',
            subtitle: 'Receivables statement for a specific customer',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CustomerLedgerPickerScreen())),
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
