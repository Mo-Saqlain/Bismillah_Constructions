import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/party.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../common/ledger_view.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

class SupplierLedgerScreen extends ConsumerStatefulWidget {
  const SupplierLedgerScreen({super.key, required this.supplierId});
  final String supplierId;

  @override
  ConsumerState<SupplierLedgerScreen> createState() =>
      _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends ConsumerState<SupplierLedgerScreen> {
  String? _projectFilter;
  Party? _supplier;
  List<JournalEntry> _rows = const [];
  List<Project> _projects = const [];
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final ent = await ref.read(entityRepoProvider.future);
    final ledger = await ref.read(ledgerRepoProvider.future);
    final all = await ledger.entriesForSupplier(widget.supplierId,
        projectId: _projectFilter);
    _rows =
        all.where((r) => r.accountId == Accounts.supplierPayables.id).toList();
    _supplier = await ent.supplier(widget.supplierId);
    _projects = await ent.projects();
  }

  void _setFilter(String? v) {
    setState(() {
      _projectFilter = v;
      _future = _load();
    });
  }

  /// Convention for a supplier-payables ledger: credits increase the
  /// outstanding amount; debits (settlements) bring it down.
  List<LedgerRow> _toRows(List<JournalEntry> entries) {
    double running = 0;
    return entries.map((r) {
      running += r.credit - r.debit;
      return LedgerRow(
        date: r.createdAt,
        memo: r.description ?? '—',
        debit: r.debit,
        credit: r.credit,
        balance: running,
      );
    }).toList();
  }

  Future<void> _exportPdf() async {
    final s = _supplier;
    if (s == null) return;
    await PdfGenerator.previewSupplierLedger(SupplierLedgerData(
      supplierName: s.name,
      rows: _rows,
      generatedAt: DateTime.now(),
    ));
  }

  Future<void> _exportCsv() async {
    final s = _supplier;
    if (s == null) return;
    final rows = _toRows(_rows);
    final csv = CsvExport.build(
      headers: ['Date', 'Memo', 'Debit', 'Credit', 'Balance'],
      rows: rows
          .map((r) => [
                fmtDate(r.date),
                r.memo,
                r.debit > 0 ? r.debit.toStringAsFixed(2) : '',
                r.credit > 0 ? r.credit.toStringAsFixed(2) : '',
                r.balance.toStringAsFixed(2),
              ])
          .toList(),
    );
    await CsvExport.share(
      fileName:
          'supplier_ledger_${s.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Supplier Ledger — ${s.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ledgerVersionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Ledger'),
        actions: [
          LedgerExportActions(
            enabled: _rows.isNotEmpty,
            onExportPdf: _exportPdf,
            onExportCsv: _exportCsv,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final supplier = _supplier;
          if (supplier == null) {
            return const Center(child: Text('Supplier not found.'));
          }
          final ledgerRows = _toRows(_rows);
          final total =
              _rows.fold<double>(0, (a, r) => a + r.credit - r.debit);

          return LedgerView(
            title: supplier.name,
            subtitle: [
              if (supplier.phone != null) supplier.phone,
              if (supplier.category != null) supplier.category!.label,
            ].whereType<String>().join(' · '),
            rows: ledgerRows,
            totalLabel: 'Net Outstanding',
            totalValue: total,
            emptyMessage: 'No transactions with this supplier yet.',
            headerBelowTitle: DropdownButtonFormField<String>(
              initialValue: _projectFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by Project (optional)',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('All Projects')),
                ..._projects.map((p) =>
                    DropdownMenuItem(value: p.id, child: Text(p.name))),
              ],
              onChanged: _setFilter,
            ),
          );
        },
      ),
    );
  }
}

class SupplierLedgerPickerScreen extends ConsumerWidget {
  const SupplierLedgerPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Supplier')),
      body: AsyncView<List<Party>>(
        value: suppliers,
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Add a supplier first.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = list[i];
              return Card(
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.local_shipping)),
                  title: Text(s.name),
                  subtitle:
                      s.category != null ? Text(s.category!.label) : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SupplierLedgerScreen(supplierId: s.id),
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
