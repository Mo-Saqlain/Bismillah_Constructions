import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/party.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
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

  Future<({Party? supplier, List<JournalEntry> rows, List<Project> projects})>
      _load() async {
    final ent = await ref.read(entityRepoProvider.future);
    final ledger = await ref.read(ledgerRepoProvider.future);
    final all = await ledger.entriesForSupplier(widget.supplierId,
        projectId: _projectFilter);
    final rows =
        all.where((r) => r.accountId == Accounts.supplierPayables.id).toList();
    final s = await ent.supplier(widget.supplierId);
    final projects = await ent.projects();
    return (supplier: s, rows: rows, projects: projects);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ledgerVersionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Supplier Ledger')),
      body: FutureBuilder<
          ({Party? supplier, List<JournalEntry> rows, List<Project> projects})>(
        future: _load(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (:supplier, :rows, :projects) = snap.data!;
          if (supplier == null) {
            return const Center(child: Text('Supplier not found.'));
          }
          double running = 0;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(supplier.name,
                  style: Theme.of(context).textTheme.titleLarge),
              if (supplier.phone != null) Text(supplier.phone!),
              if (supplier.category != null)
                Text('Category: ${supplier.category!.label}',
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              // Project filter dropdown
              DropdownButtonFormField<String>(
                initialValue: _projectFilter,
                decoration: const InputDecoration(
                    labelText: 'Filter by Project (optional)',
                    isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Projects')),
                  ...projects.map((p) =>
                      DropdownMenuItem(value: p.id, child: Text(p.name))),
                ],
                onChanged: (v) => setState(() => _projectFilter = v),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No transactions with this supplier yet.')),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            _H('Date', flex: 3),
                            _H('Memo', flex: 4),
                            _H('Dr', flex: 2, right: true),
                            _H('Cr', flex: 2, right: true),
                            _H('Bal', flex: 3, right: true),
                          ],
                        ),
                        const Divider(),
                        ...rows.map((r) {
                          running += r.credit - r.debit;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                _C(fmtDate(r.createdAt), flex: 3),
                                _C(r.description ?? '—', flex: 4),
                                _C(r.debit > 0 ? fmtMoney(r.debit) : '',
                                    flex: 2, right: true),
                                _C(r.credit > 0 ? fmtMoney(r.credit) : '',
                                    flex: 2, right: true),
                                _C(fmtMoney(running),
                                    flex: 3, right: true, bold: true),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net Outstanding',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      fmtMoney(rows.fold<double>(
                          0, (a, r) => a + r.credit - r.debit)),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export as PDF'),
                onPressed: rows.isEmpty
                    ? null
                    : () => PdfGenerator.previewSupplierLedger(
                          SupplierLedgerData(
                            supplierName: supplier.name,
                            rows: rows,
                            generatedAt: DateTime.now(),
                          ),
                        ),
              ),
            ],
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
                  leading: const CircleAvatar(
                      child: Icon(Icons.local_shipping)),
                  title: Text(s.name),
                  subtitle: s.category != null ? Text(s.category!.label) : null,
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

class _H extends StatelessWidget {
  const _H(this.text, {required this.flex, this.right = false});
  final String text;
  final int flex;
  final bool right;
  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(text,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 12)),
      );
}

class _C extends StatelessWidget {
  const _C(this.text,
      {required this.flex, this.right = false, this.bold = false});
  final String text;
  final int flex;
  final bool right;
  final bool bold;
  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(text,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
      );
}
