import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/party.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../common/date_range_bar.dart';
import '../common/ledger_view.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

/// Picker for the Wage Ledger — only labour-category suppliers (and
/// uncategorised legacy ones) appear, since the wage ledger is a per-worker
/// view of Labour Costs debits.
class WageLedgerPickerScreen extends ConsumerWidget {
  const WageLedgerPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Wage Ledger')),
      body: AsyncView<List<Party>>(
        value: suppliers,
        data: (list) {
          final workers = list
              .where((s) =>
                  s.category == null || s.category == SupplierCategory.labor)
              .toList();
          if (workers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No labour-category suppliers yet. Add one from Manage → Suppliers.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: workers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final w = workers[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.engineering)),
                  title: Text(w.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: w.phone != null ? Text('Ph: ${w.phone}') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WageLedgerScreen(worker: w),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Per-worker wage ledger. Shows every Labour Costs debit charged against
/// this worker (whether it came from a [TxnKind.labourPayment] or a
/// [TxnKind.labourCredit]) with a running cumulative-wages total. Honours
/// the same date filter the other ledgers use.
class WageLedgerScreen extends ConsumerStatefulWidget {
  const WageLedgerScreen({super.key, required this.worker});
  final Party worker;

  @override
  ConsumerState<WageLedgerScreen> createState() => _WageLedgerScreenState();
}

class _WageLedgerScreenState extends ConsumerState<WageLedgerScreen> {
  DateTime? _from;
  DateTime? _to;

  /// Wages-only ledger — every entry is a Labour Costs debit. Running
  /// total = cumulative wages this worker has earned over the period.
  List<LedgerRow> _toRows(List<JournalEntry> entries) {
    double running = 0;
    return entries.map((e) {
      running += e.debit;
      return LedgerRow(
        date: e.createdAt,
        memo: e.description ?? '—',
        debit: e.debit,
        credit: 0,
        balance: running,
      );
    }).toList();
  }

  Future<void> _exportPdf(List<JournalEntry> entries) async {
    await PdfGenerator.previewWorkerLedger(WorkerLedgerData(
      workerName: widget.worker.name,
      rows: entries,
      generatedAt: DateTime.now(),
      period: formatPeriod(_from, _to),
    ));
  }

  Future<void> _exportCsv(List<JournalEntry> entries) async {
    final rows = _toRows(entries);
    final total = rows.fold<double>(0, (a, r) => a + r.debit);
    final csv = CsvExport.build(
      headers: const [
        'Date',
        'Particulars',
        'Wages (Debit)',
        'Cumulative'
      ],
      rows: [
        ['Worker:', widget.worker.name, '', ''],
        if (widget.worker.phone != null)
          ['Phone:', widget.worker.phone!, '', ''],
        ['Period:', formatPeriod(_from, _to), '', ''],
        ['', '', '', ''],
        ...rows.map((r) => [
              fmtDate(r.date),
              r.memo,
              r.debit.toStringAsFixed(2),
              r.balance.toStringAsFixed(2),
            ]),
        ['', '', '', ''],
        ['Total:', '', total.toStringAsFixed(2), ''],
      ],
    );
    await CsvExport.share(
      fileName:
          'wage_ledger_${widget.worker.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Wage Ledger — ${widget.worker.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ledgerVersionProvider);
    final entriesAsync = ref.watch(_workerEntriesProvider(_WageFilterKey(
      supplierId: widget.worker.id,
      from: _from,
      to: _to,
    )));

    return Scaffold(
      appBar: AppBar(
        title: Text('Wage · ${widget.worker.name}'),
        actions: [
          LedgerExportActions(
            enabled: entriesAsync.hasValue &&
                (entriesAsync.value?.isNotEmpty ?? false),
            onExportPdf: () async {
              final e = await ref.read(_workerEntriesProvider(_WageFilterKey(
                supplierId: widget.worker.id,
                from: _from,
                to: _to,
              )).future);
              await _exportPdf(e);
            },
            onExportCsv: () async {
              final e = await ref.read(_workerEntriesProvider(_WageFilterKey(
                supplierId: widget.worker.id,
                from: _from,
                to: _to,
              )).future);
              await _exportCsv(e);
            },
          ),
        ],
      ),
      body: AsyncView<List<JournalEntry>>(
        value: entriesAsync,
        data: (entries) {
          final rows = _toRows(entries);
          final total = rows.isEmpty ? 0.0 : rows.last.balance;
          return LedgerView(
            title: widget.worker.name,
            subtitle: '${widget.worker.phone == null ? '' : 'Ph: ${widget.worker.phone} · '}'
                'Period: ${formatPeriod(_from, _to)}',
            rows: rows,
            totalLabel: 'Total Wages',
            totalValue: total,
            debitHeader: 'Wages',
            // Wage ledger has no credit side — every row is a debit.
            // Hide the column heading so the table doesn't look broken.
            creditHeader: '',
            balanceHeader: 'Cumulative',
            emptyMessage: 'No wages recorded for this worker in the period.',
            headerBelowTitle: DateRangeBar(
              from: _from,
              to: _to,
              onChanged: (f, t) => setState(() {
                _from = f;
                _to = t;
              }),
            ),
          );
        },
      ),
    );
  }
}

class _WageFilterKey {
  final String supplierId;
  final DateTime? from;
  final DateTime? to;
  const _WageFilterKey({required this.supplierId, this.from, this.to});

  @override
  bool operator ==(Object other) =>
      other is _WageFilterKey &&
      other.supplierId == supplierId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(supplierId, from, to);
}

final _workerEntriesProvider =
    FutureProvider.family<List<JournalEntry>, _WageFilterKey>((ref, key) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.entriesForWorker(key.supplierId, from: key.from, to: key.to);
});
