import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../providers/providers.dart';
import 'csv_export.dart';

/// Cash Flow Statement — monthly Δ-cash per cash-like account (Cash,
/// Supervisor Float, plus every user-defined bank/wallet).
class CashFlowScreen extends ConsumerWidget {
  const CashFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final dataAsync = ref.watch(_cashFlowProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: () async {
              final bundle = await ref.read(_cashFlowProvider.future);
              await _exportCsv(bundle);
            },
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bundle) {
          if (bundle.rows.every((r) => r.total == 0)) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No cash movement in the last 12 months.'),
            ));
          }
          final monthFmt = DateFormat('MMM yy');
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Month')),
                      ...bundle.accounts.map(
                          (a) => DataColumn(label: Text(_short(a.name)))),
                      const DataColumn(label: Text('Total Δ'), numeric: true),
                    ],
                    rows: [
                      for (final m in bundle.rows)
                        DataRow(cells: [
                          DataCell(Text(monthFmt.format(m.month.toLocal()))),
                          ...bundle.accounts.map((a) {
                            final v = m.perAccount[a.id] ?? 0;
                            return DataCell(Text(
                              v == 0 ? '—' : fmtSignedMoney(v),
                              style: TextStyle(
                                  color: v == 0
                                      ? null
                                      : BalanceColors.signed(context, v)),
                            ));
                          }),
                          DataCell(Text(fmtSignedMoney(m.total),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: BalanceColors.signed(
                                      context, m.total)))),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Each row is the net change (debits − credits) per cash-like '
                'account in that calendar month.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _short(String name) {
    if (name.length <= 10) return name;
    final parts = name.split(' ');
    return parts.length > 1 ? parts.last : name.substring(0, 10);
  }

  Future<void> _exportCsv(_CashFlowBundle bundle) async {
    final monthFmt = DateFormat('yyyy-MM');
    final csv = CsvExport.build(
      headers: [
        'Month',
        ...bundle.accounts.map((a) => a.name),
        'Total',
      ],
      rows: [
        for (final m in bundle.rows)
          [
            monthFmt.format(m.month),
            ...bundle.accounts
                .map((a) => (m.perAccount[a.id] ?? 0).toStringAsFixed(2)),
            m.total.toStringAsFixed(2),
          ],
      ],
    );
    await CsvExport.share(
      fileName: 'cash_flow_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Cash Flow Statement',
    );
  }
}

class _CashFlowBundle {
  final List<MonthlyCashFlow> rows;
  final List<Account> accounts;
  const _CashFlowBundle(this.rows, this.accounts);
}

final _cashFlowProvider = FutureProvider<_CashFlowBundle>((ref) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  final accounts = await ref.watch(cashLikeAccountsProvider.future);
  final rows = await repo.monthlyCashFlow();
  return _CashFlowBundle(rows, accounts);
});
