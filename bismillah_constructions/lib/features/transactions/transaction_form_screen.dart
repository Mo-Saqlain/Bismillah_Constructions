import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/material_item.dart';
import '../../data/models/party.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, required this.kind});
  final TxnKind kind;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState
    extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  String? _projectId;
  String? _supplierId;
  String? _customerId;
  Account _cashLike = Accounts.cash;
  Account _transferTo = Accounts.bankHbl;
  MaterialType _materialType = MaterialType.cement;
  bool _saving = false;

  TxnKind get _k => widget.kind;
  bool get _isMaterialBuy => _k == TxnKind.materialBuy;
  bool get _isWalletTransfer => _k == TxnKind.walletTransfer;
  bool get _isPersonalDraw => _k == TxnKind.personalDraw;
  bool get _isServiceFee => _k == TxnKind.serviceFee;

  bool get _needsProject => switch (_k) {
        TxnKind.materialBuy ||
        TxnKind.labourPayment ||
        TxnKind.clientBilling ||
        TxnKind.serviceFee =>
          true,
        _ => false,
      };

  bool get _needsSupplier => switch (_k) {
        TxnKind.materialBuy ||
        TxnKind.supplierPay ||
        TxnKind.labourPayment =>
          true,
        _ => false,
      };

  bool get _needsOptionalProject => _k == TxnKind.supplierPay;

  bool get _needsCustomer => switch (_k) {
        TxnKind.clientBilling || TxnKind.receivePayment => true,
        _ => false,
      };

  bool get _needsCashLike => switch (_k) {
        TxnKind.labourPayment ||
        TxnKind.supplierPay ||
        TxnKind.receivePayment ||
        TxnKind.walletTransfer ||
        TxnKind.personalDraw ||
        TxnKind.serviceFee =>
          true,
        _ => false,
      };

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _quantityCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  double? _computedMaterialTotal() {
    final qty = double.tryParse(_quantityCtrl.text);
    final rate = double.tryParse(_rateCtrl.text);
    if (qty == null || rate == null || qty <= 0 || rate <= 0) return null;
    return MaterialItem.computeTotal(_materialType, qty, rate);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isWalletTransfer && _cashLike.id == _transferTo.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Source and destination must differ.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final ledger = await ref.read(ledgerRepoProvider.future);
      final desc =
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();

      final amount = _isMaterialBuy
          ? _computedMaterialTotal()!
          : double.parse(_amountCtrl.text);

      String txnId;
      switch (_k) {
        case TxnKind.materialBuy:
          txnId = await ledger.postMaterialBuy(
              amount: amount,
              projectId: _projectId!,
              supplierId: _supplierId!,
              description: desc);
          final entityRepo = await ref.read(entityRepoProvider.future);
          await entityRepo.logMaterialPurchase(
            projectId: _projectId!,
            supplierId: _supplierId!,
            transactionId: txnId,
            materialType: _materialType,
            quantity: double.parse(_quantityCtrl.text),
            rate: double.parse(_rateCtrl.text),
          );
        case TxnKind.labourPayment:
          txnId = await ledger.postLabourPayment(
              amount: amount,
              projectId: _projectId!,
              supplierId: _supplierId!,
              paidFrom: _cashLike,
              description: desc);
        case TxnKind.supplierPay:
          txnId = await ledger.postSupplierPay(
              amount: amount,
              supplierId: _supplierId!,
              paidFrom: _cashLike,
              projectId: _projectId,
              description: desc);
        case TxnKind.clientBilling:
          txnId = await ledger.postClientBilling(
              amount: amount,
              customerId: _customerId!,
              projectId: _projectId!,
              description: desc);
        case TxnKind.receivePayment:
          txnId = await ledger.postReceivePayment(
              amount: amount,
              customerId: _customerId!,
              receivedInto: _cashLike,
              description: desc);
        case TxnKind.walletTransfer:
          txnId = await ledger.postWalletTransfer(
              amount: amount,
              from: _cashLike,
              to: _transferTo,
              description: desc);
        case TxnKind.personalDraw:
          txnId = await ledger.postPersonalDraw(
              amount: amount,
              paidFrom: _cashLike,
              description: desc);
        case TxnKind.serviceFee:
          txnId = await ledger.postServiceFee(
              amount: amount,
              projectId: _projectId!,
              receivedInto: _cashLike,
              description: desc);
      }
      // Use txnId to silence unused warning; available for future routing.
      assert(txnId.isNotEmpty);

      bumpLedger(ref);
      final svc = await ref.read(syncServiceFutureProvider.future);
      // ignore: unawaited_futures
      svc.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_k.label} saved')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(activeProjectsProvider);
    final customers = ref.watch(customersProvider);
    final suppliers = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_k.label)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RoutingSummary(kind: _k),
              const SizedBox(height: 16),

              if (_isMaterialBuy) ...[
                DropdownButtonFormField<MaterialType>(
                  initialValue: _materialType,
                  decoration:
                      const InputDecoration(labelText: 'Material Type'),
                  items: MaterialType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _materialType = v ?? _materialType),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantityCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: InputDecoration(
                          labelText:
                              'Quantity (${_materialType.defaultUnit.label})',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = double.tryParse(v);
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: _materialType == MaterialType.brick
                              ? 'Rate (per 1000)'
                              : 'Rate (per unit)',
                          prefixText: 'Rs ',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = double.tryParse(v);
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _TotalPreview(total: _computedMaterialTotal()),
              ] else ...[
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Amount (Rs)',
                    prefixText: 'Rs ',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter an amount';
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) return 'Must be a positive number';
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 16),

              if (_needsProject)
                AsyncView<List<Project>>(
                  value: projects,
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _projectId,
                    decoration: InputDecoration(
                        labelText: _isServiceFee
                            ? 'Project (for service fee)'
                            : 'Project'),
                    items: list
                        .map((p) => DropdownMenuItem(
                            value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _projectId = v),
                    validator: (v) => v == null ? 'Select a project' : null,
                  ),
                ),

              if (_needsOptionalProject) ...[
                const SizedBox(height: 12),
                AsyncView<List<Project>>(
                  value: projects,
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _projectId,
                    decoration: const InputDecoration(
                        labelText:
                            'Project (optional — links payment to project)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— None —')),
                      ...list.map((p) => DropdownMenuItem(
                          value: p.id, child: Text(p.name))),
                    ],
                    onChanged: (v) => setState(() => _projectId = v),
                  ),
                ),
              ],

              if (_needsSupplier) ...[
                const SizedBox(height: 12),
                AsyncView<List<Party>>(
                  value: suppliers,
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _supplierId,
                    decoration: InputDecoration(
                      labelText: _k == TxnKind.labourPayment
                          ? 'Labour Provider (Supplier)'
                          : 'Supplier',
                    ),
                    items: list
                        .map((s) => DropdownMenuItem(
                            value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _supplierId = v),
                    validator: (v) => v == null ? 'Select a supplier' : null,
                  ),
                ),
              ],

              if (_needsCustomer) ...[
                const SizedBox(height: 12),
                AsyncView<List<Party>>(
                  value: customers,
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _customerId,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: list
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _customerId = v),
                    validator: (v) => v == null ? 'Select a customer' : null,
                  ),
                ),
              ],

              if (_needsCashLike) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Account>(
                  initialValue: _cashLike,
                  decoration: InputDecoration(
                    labelText: switch (_k) {
                      TxnKind.receivePayment => 'Receive Into',
                      TxnKind.serviceFee => 'Receive Into',
                      TxnKind.walletTransfer => 'From Wallet',
                      _ => 'Pay From',
                    },
                  ),
                  items: Accounts.cashLikeAccounts
                      .map((a) =>
                          DropdownMenuItem(value: a, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _cashLike = v ?? _cashLike),
                ),
              ],

              if (_isWalletTransfer) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Account>(
                  initialValue: _transferTo,
                  decoration: const InputDecoration(labelText: 'To Wallet'),
                  items: Accounts.cashLikeAccounts
                      .map((a) =>
                          DropdownMenuItem(value: a, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _transferTo = v ?? _transferTo),
                ),
                const SizedBox(height: 8),
                Text(
                  'Note: Inter-wallet movement does not reduce supplier payables.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],

              if (_isPersonalDraw) ...[
                const SizedBox(height: 8),
                Text(
                  'Recorded as a Personal/Daily Draw. Project liabilities remain intact.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],

              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Description / Memo (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving…' : 'Save Transaction'),
              ),
              const SizedBox(height: 12),
              const _OfflineNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalPreview extends StatelessWidget {
  const _TotalPreview({required this.total});
  final double? total;

  @override
  Widget build(BuildContext context) {
    if (total == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Calculated Total',
              style: Theme.of(context).textTheme.bodyMedium),
          Text(
            'Rs ${total!.toStringAsFixed(2)}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RoutingSummary extends StatelessWidget {
  const _RoutingSummary({required this.kind});
  final TxnKind kind;

  ({String dr, String cr}) _route() => switch (kind) {
        TxnKind.materialBuy => (
            dr: Accounts.materialCosts.name,
            cr: Accounts.supplierPayables.name
          ),
        TxnKind.labourPayment => (
            dr: Accounts.labourCosts.name,
            cr: 'Cash / Bank'
          ),
        TxnKind.supplierPay => (
            dr: Accounts.supplierPayables.name,
            cr: 'Cash / Bank'
          ),
        TxnKind.clientBilling => (
            dr: Accounts.clientReceivables.name,
            cr: Accounts.projectRevenue.name
          ),
        TxnKind.receivePayment => (
            dr: 'Cash / Bank',
            cr: Accounts.clientReceivables.name
          ),
        TxnKind.walletTransfer => (
            dr: 'Destination Wallet',
            cr: 'Source Wallet'
          ),
        TxnKind.personalDraw => (
            dr: Accounts.personalDraw.name,
            cr: 'Cash / Bank'
          ),
        TxnKind.serviceFee => (
            dr: 'Cash / Bank',
            cr: Accounts.serviceFeeIncome.name
          ),
      };

  @override
  Widget build(BuildContext context) {
    final r = _route();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Posting',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Dr  ${r.dr}'),
          Text('     Cr  ${r.cr}'),
        ],
      ),
    );
  }
}

class _OfflineNote extends ConsumerWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text(
      'Saved locally first. Cloud sync runs automatically when online.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
