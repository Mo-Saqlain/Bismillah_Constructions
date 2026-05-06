import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

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
                _StatusBanner(
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ok: false,
                  message:
                      'Assets do not equal Liabilities + Equity. Difference: ${fmtMoney(s.assets - liabPlusEquity)}',
                )
              else
                _StatusBanner(
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ok: true,
                  message: 'Books are balanced.',
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                      onPressed: () async {
                        final list = await ref.read(banksProvider.future);
                        await PdfGenerator.previewBalanceSheet(
                          BalanceSheetData(
                            cash: s.cash,
                            bankRows: [
                              for (final b in list)
                                (b.name, s.bankBalances[b.id] ?? 0),
                            ],
                            counterReceivables: s.counterReceivables,
                            payables: s.payables,
                            counterPayables: s.counterPayables,
                            equity: s.equity,
                            generatedAt: DateTime.now(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.file_download),
                      label: const Text('CSV'),
                      onPressed: () async {
                        final list = await ref.read(banksProvider.future);
                        final csv = CsvExport.build(
                          headers: ['Line', 'Amount'],
                          rows: [
                            ['Cash', s.cash.toStringAsFixed(2)],
                            for (final b in list)
                              [
                                b.name,
                                (s.bankBalances[b.id] ?? 0).toStringAsFixed(2)
                              ],
                            if (s.counterReceivables > 0)
                              ['Counter Receivables',
                                  s.counterReceivables.toStringAsFixed(2)],
                            ['Total Assets', s.assets.toStringAsFixed(2)],
                            ['Supplier Payables',
                                s.payables.toStringAsFixed(2)],
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
                  ),
                ],
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

/// Banner that adapts to dark mode. The "ok" state used to be green; the app
/// now uses blue everywhere so positive feedback inherits the primary palette
/// instead. Negative state stays red (universal accounting convention).
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.ok,
    required this.message,
    required this.isDark,
  });
  final bool ok;
  final String message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = ok
        ? (isDark ? Colors.blue.shade900 : Colors.blue.shade50)
        : (isDark ? Colors.red.shade900 : Colors.red.shade50);
    final fg = ok
        ? (isDark ? Colors.blue.shade100 : Colors.blue.shade900)
        : (isDark ? Colors.red.shade100 : Colors.red.shade900);
    final border = ok
        ? (isDark ? Colors.blue.shade400 : Colors.blue.shade300)
        : (isDark ? Colors.red.shade400 : Colors.red.shade300);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
