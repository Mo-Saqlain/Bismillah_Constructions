import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/party.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../reports/customer_ledger_screen.dart';
import '../reports/supplier_ledger_screen.dart';

enum PartyKind { customer, supplier }

class PartiesScreen extends ConsumerWidget {
  const PartiesScreen({super.key, required this.kind});
  final PartyKind kind;

  String get _title => kind == PartyKind.customer ? 'Customers' : 'Suppliers';
  String get _singular => kind == PartyKind.customer ? 'Customer' : 'Supplier';
  IconData get _icon =>
      kind == PartyKind.customer ? Icons.person : Icons.local_shipping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = kind == PartyKind.customer
        ? ref.watch(customersProvider)
        : ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.add),
        label: Text('New $_singular'),
      ),
      body: AsyncView<List<Party>>(
        value: list,
        data: (parties) {
          if (parties.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon, size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('No ${_title.toLowerCase()} yet',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: parties.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = parties[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_icon)),
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: _buildSubtitle(p),
                  trailing: Text(fmtDate(p.createdAt),
                      style: Theme.of(context).textTheme.bodySmall),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => kind == PartyKind.supplier
                          ? SupplierLedgerScreen(supplierId: p.id)
                          : CustomerLedgerScreen(customerId: p.id),
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

  Widget? _buildSubtitle(Party p) {
    final lines = <String>[];
    if (p.phone != null) lines.add(p.phone!);
    if (kind == PartyKind.customer) {
      if (p.ntnCnic != null) lines.add('NTN/CNIC: ${p.ntnCnic}');
      if (p.address != null) lines.add(p.address!);
      if (p.creditLimit != null) {
        lines.add('Credit Limit: ${fmtMoney(p.creditLimit!)}');
      }
    } else {
      if (p.category != null) lines.add(p.category!.label);
      if (p.taxStatus != null) lines.add('Tax: ${p.taxStatus}');
    }
    if (lines.isEmpty) return null;
    return Text(lines.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis);
  }

  void _showForm(BuildContext context, WidgetRef ref) {
    if (kind == PartyKind.customer) {
      _showCustomerForm(context, ref);
    } else {
      _showSupplierForm(context, ref);
    }
  }

  void _showCustomerForm(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ntnCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final creditCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Customer',
                  style: Theme.of(sheetCtx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name *'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration:
                    const InputDecoration(labelText: 'Phone (optional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ntnCtrl,
                decoration:
                    const InputDecoration(labelText: 'NTN / CNIC (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: creditCtrl,
                decoration: const InputDecoration(
                    labelText: 'Credit Limit (optional)', prefixText: 'Rs '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final repo = await ref.read(entityRepoProvider.future);
                  await repo.createCustomer(
                    name: name,
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                    ntnCnic:
                        ntnCtrl.text.trim().isEmpty ? null : ntnCtrl.text.trim(),
                    address: addressCtrl.text.trim().isEmpty
                        ? null
                        : addressCtrl.text.trim(),
                    creditLimit: double.tryParse(creditCtrl.text),
                  );
                  bumpLedger(ref);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                },
                child: const Text('Create'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupplierForm(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final taxCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    SupplierCategory? category;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Supplier',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SupplierCategory>(
                  initialValue: category,
                  decoration:
                      const InputDecoration(labelText: 'Category (optional)'),
                  items: SupplierCategory.values
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c.label)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => category = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: taxCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Tax status (optional)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Bank details (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final repo = await ref.read(entityRepoProvider.future);
                    await repo.createSupplier(
                      name: name,
                      phone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      category: category,
                      taxStatus: taxCtrl.text.trim().isEmpty
                          ? null
                          : taxCtrl.text.trim(),
                      bankDetails: bankCtrl.text.trim().isEmpty
                          ? null
                          : bankCtrl.text.trim(),
                    );
                    bumpLedger(ref);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                  child: const Text('Create'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
