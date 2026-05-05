import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/models/party.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../providers/providers.dart';
import 'csv_export.dart';

class WageRegisterScreen extends ConsumerWidget {
  const WageRegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final dataAsync = ref.watch(_wageBundleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wage Register'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: () async {
              final bundle = await ref.read(_wageBundleProvider.future);
              await _exportCsv(bundle);
            },
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bundle) {
          if (bundle.lines.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No labour payments recorded yet.'),
            ));
          }
          final names = {for (final s in bundle.suppliers) s.id: s.name};
          final grandTotal = bundle.lines
              .fold<double>(0, (s, l) => s + l.totalPaid);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Total Labour Paid'),
                      const SizedBox(height: 4),
                      Text(fmtMoney(grandTotal),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${bundle.lines.length} workers · '
                          '${bundle.lines.fold<int>(0, (s, l) => s + l.paymentCount)} payments'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Worker / Supplier')),
                      DataColumn(label: Text('Payments'), numeric: true),
                      DataColumn(label: Text('Total Paid'), numeric: true),
                      DataColumn(label: Text('Last Paid')),
                    ],
                    rows: [
                      for (final l in bundle.lines)
                        DataRow(cells: [
                          DataCell(Text(names[l.supplierId] ??
                              l.supplierId.substring(0, 6))),
                          DataCell(Text('${l.paymentCount}')),
                          DataCell(Text(fmtMoney(l.totalPaid),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(fmtDate(l.lastPaidAt))),
                        ]),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportCsv(_WageBundle bundle) async {
    final names = {for (final s in bundle.suppliers) s.id: s.name};
    final csv = CsvExport.build(
      headers: ['Worker', 'Payments', 'Total Paid', 'Last Paid'],
      rows: [
        for (final l in bundle.lines)
          [
            names[l.supplierId] ?? l.supplierId,
            l.paymentCount,
            l.totalPaid.toStringAsFixed(2),
            l.lastPaidAt.toIso8601String(),
          ],
      ],
    );
    await CsvExport.share(
      fileName: 'wage_register_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Wage Register',
    );
  }
}

class _WageBundle {
  final List<WageRegisterLine> lines;
  final List<Party> suppliers;
  const _WageBundle(this.lines, this.suppliers);
}

final _wageBundleProvider = FutureProvider<_WageBundle>((ref) async {
  ref.watch(ledgerVersionProvider);
  final ledger = await ref.watch(ledgerRepoProvider.future);
  final entityRepo = await ref.watch(entityRepoProvider.future);
  final lines = await ledger.wageRegister();
  final suppliers = await entityRepo.suppliers();
  return _WageBundle(lines, suppliers);
});
