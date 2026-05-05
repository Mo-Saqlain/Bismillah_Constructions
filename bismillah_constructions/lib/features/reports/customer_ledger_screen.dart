import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/party.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import 'pdf_generator.dart';

class CustomerLedgerScreen extends ConsumerWidget {
  const CustomerLedgerScreen({super.key, required this.customerId});
  final String customerId;

  Future<({Party? customer, List<JournalEntry> rows})> _load(
      WidgetRef ref) async {
    final ent = await ref.read(entityRepoProvider.future);
    final ledger = await ref.read(ledgerRepoProvider.future);
    // Only receivable-side movements make up the customer statement.
    final rows = (await ledger.entriesForCustomer(customerId))
        .where((r) => r.accountId == Accounts.clientReceivables.id)
        .toList();
    final c = await ent.customer(customerId);
    return (customer: c, rows: rows);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final fut = _load(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Ledger')),
      body: FutureBuilder<({Party? customer, List<JournalEntry> rows})>(
        future: fut,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (:customer, :rows) = snap.data!;
          if (customer == null) {
            return const Center(child: Text('Customer not found.'));
          }
          double running = 0;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(customer.name,
                  style: Theme.of(context).textTheme.titleLarge),
              if (customer.phone != null) Text(customer.phone!),
              if (customer.address != null)
                Text(customer.address!,
                    style: Theme.of(context).textTheme.bodySmall),
              if (customer.creditLimit != null)
                Text('Credit Limit: ${fmtMoney(customer.creditLimit!)}',
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No transactions with this customer yet.')),
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
                          running += r.debit - r.credit;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
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
                    const Text('Net Receivable',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      fmtMoney(rows.fold<double>(
                          0, (a, r) => a + r.debit - r.credit)),
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
                            supplierName: customer.name,
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

class CustomerLedgerPickerScreen extends ConsumerWidget {
  const CustomerLedgerPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Customer')),
      body: AsyncView<List<Party>>(
        value: customers,
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Add a customer first.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = list[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(c.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CustomerLedgerScreen(customerId: c.id),
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

// Tiny helpers for the table — shared style with supplier_ledger_screen.
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
