import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import 'csv_export.dart';

class BalanceSheetScreen extends ConsumerWidget {
  const BalanceSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(accountSummaryProvider);
    final banks = ref.watch(banksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Balance Sheet')),
      body: AsyncView(
        value: summary,
        data: (s) {
          final liabPlusEquity = s.liabilities + s.equity;
          final balanced = (s.assets - liabPlusEquity).abs() < 0.01;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Assets',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      _row('Cash', s.cash),
                      _row('Supervisor Float', s.supervisorFloat),
                      AsyncView(
                        value: banks,
                        data: (list) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final b in list)
                              _row(b.name, s.bankBalances[b.id] ?? 0),
                          ],
                        ),
                      ),
                      if (s.counterReceivables > 0)
                        _row('Counter Receivables', s.counterReceivables),
                      const Divider(),
                      _row('Total Assets', s.assets, bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Liabilities & Equity',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      _row('Supplier Payables', s.payables),
                      if (s.counterPayables > 0)
                        _row('Counter Payables', s.counterPayables),
                      _row("Owner's Equity (derived)", s.equity),
                      const Divider(),
                      _row('Total Liabilities + Equity', liabPlusEquity,
                          bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!balanced)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Assets do not equal Liabilities + Equity. '
                          'Difference: ${fmtMoney(s.assets - liabPlusEquity)}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Books are balanced.'),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.file_download),
                label: const Text('Export CSV'),
                onPressed: () async {
                  final list = await ref.read(banksProvider.future);
                  final csv = CsvExport.build(
                    headers: ['Line', 'Amount'],
                    rows: [
                      ['Cash', s.cash.toStringAsFixed(2)],
                      ['Supervisor Float',
                          s.supervisorFloat.toStringAsFixed(2)],
                      for (final b in list)
                        [b.name,
                            (s.bankBalances[b.id] ?? 0).toStringAsFixed(2)],
                      if (s.counterReceivables > 0)
                        ['Counter Receivables',
                            s.counterReceivables.toStringAsFixed(2)],
                      ['Total Assets', s.assets.toStringAsFixed(2)],
                      ['Supplier Payables', s.payables.toStringAsFixed(2)],
                      if (s.counterPayables > 0)
                        ['Counter Payables',
                            s.counterPayables.toStringAsFixed(2)],
                      ["Owner's Equity", s.equity.toStringAsFixed(2)],
                      ['Total Liabilities + Equity',
                          liabPlusEquity.toStringAsFixed(2)],
                    ],
                  );
                  await CsvExport.share(
                    fileName:
                        'balance_sheet_${DateTime.now().millisecondsSinceEpoch}',
                    csv: csv,
                    subject: 'Balance Sheet',
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.w700 : FontWeight.normal)),
            Text(fmtMoney(v),
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.w700 : FontWeight.normal)),
          ],
        ),
      );
}
