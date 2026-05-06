import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/party.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../settings/material_types_screen.dart';

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
  /// Only used for [TxnKind.labourCredit] — number of workers that came in
  /// for the period being recorded. Folded into the description like
  /// `N workers · {user memo}` so the count survives in the audit log.
  final _workerCountCtrl = TextEditingController();

  String? _projectId;
  String? _supplierId;
  Account? _cashLike;
  Account? _transferTo;
  /// User-managed material category, resolved from the `materialTypesProvider`
  /// list once it loads. The dropdown defaults to the first available type.
  String? _materialType;
  bool _saving = false;

  TxnKind get _k => widget.kind;
  bool get _isMaterialBuy => _k == TxnKind.materialBuy;
  bool get _isWalletTransfer => _k == TxnKind.walletTransfer;
  bool get _isPersonalDraw => _k == TxnKind.personalDraw;
  bool get _isLabourCredit => _k == TxnKind.labourCredit;

  /// Project is REQUIRED for everything that touches a project's books.
  bool get _needsProject => switch (_k) {
        TxnKind.materialBuy ||
        TxnKind.labourPayment ||
        TxnKind.labourCredit ||
        TxnKind.receiveFromProject ||
        TxnKind.serviceFee =>
          true,
        _ => false,
      };

  /// Project is OPTIONAL for supplier-payments (they may settle a payable
  /// shared across projects).
  bool get _needsOptionalProject => _k == TxnKind.supplierPay;

  bool get _needsSupplier => switch (_k) {
        TxnKind.materialBuy ||
        TxnKind.supplierPay ||
        TxnKind.labourPayment ||
        TxnKind.labourCredit =>
          true,
        _ => false,
      };

  bool get _needsCashLike => switch (_k) {
        TxnKind.labourPayment ||
        TxnKind.supplierPay ||
        TxnKind.receiveFromProject ||
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
    _workerCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isWalletTransfer &&
        _cashLike != null &&
        _cashLike!.id == _transferTo?.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Source and destination must differ.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final ledger = await ref.read(ledgerRepoProvider.future);
      final desc =
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
      // Strip the live thousands separators before parsing — the formatter
      // injects commas for readability while the user types.
      final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));

      String txnId;
      switch (_k) {
        case TxnKind.materialBuy:
          // Defensive: the dropdown's validator should have caught this, but
          // belt-and-suspenders prevents a NPE crash on edge race conditions.
          if (_materialType == null) {
            throw StateError('Pick a material type first.');
          }
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
            materialType: _materialType!,
            price: amount,
          );
        case TxnKind.labourPayment:
          txnId = await ledger.postLabourPayment(
              amount: amount,
              projectId: _projectId!,
              supplierId: _supplierId!,
              paidFrom: _cashLike!,
              description: desc);
        case TxnKind.labourCredit:
          // Worker count gets prepended to the memo so the audit trail keeps
          // the headcount alongside the wages amount.
          final n = int.tryParse(_workerCountCtrl.text.trim());
          final memo = [
            if (n != null && n > 0) '$n worker${n == 1 ? '' : 's'}',
            ?desc,
          ].join(' · ');
          txnId = await ledger.postLabourCredit(
              amount: amount,
              projectId: _projectId!,
              supplierId: _supplierId!,
              description: memo.isEmpty ? null : memo);
        case TxnKind.supplierPay:
          txnId = await ledger.postSupplierPay(
              amount: amount,
              supplierId: _supplierId!,
              paidFrom: _cashLike!,
              projectId: _projectId,
              description: desc);
        case TxnKind.receiveFromProject:
          txnId = await ledger.postReceiveFromProject(
              amount: amount,
              projectId: _projectId!,
              receivedInto: _cashLike!,
              description: desc);
        case TxnKind.walletTransfer:
          txnId = await ledger.postWalletTransfer(
              amount: amount,
              from: _cashLike!,
              to: _transferTo!,
              description: desc);
        case TxnKind.personalDraw:
          txnId = await ledger.postPersonalDraw(
              amount: amount,
              paidFrom: _cashLike!,
              description: desc);
        case TxnKind.serviceFee:
          txnId = await ledger.postServiceFee(
              amount: amount,
              projectId: _projectId!,
              receivedInto: _cashLike!,
              description: desc);
      }
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
    final suppliers = ref.watch(suppliersProvider);
    final cashLike = ref.watch(cashLikeAccountsProvider);

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
                _MaterialTypePicker(
                  current: _materialType,
                  onChanged: (v) => setState(() => _materialType = v),
                ),
                const SizedBox(height: 12),
              ],

              if (_isLabourCredit) ...[
                TextFormField(
                  controller: _workerCountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Number of Workers',
                    helperText:
                        'How many labourers showed up for this period',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  _ThousandsSeparatorFormatter(),
                ],
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: _isMaterialBuy ? 'Price (Rs)' : 'Amount (Rs)',
                  prefixText: 'Rs ',
                  helperText: _isMaterialBuy
                      ? 'Quantity / unit details go in the memo below'
                      : null,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter an amount';
                  final n = double.tryParse(v.replaceAll(',', ''));
                  if (n == null || n <= 0) return 'Must be a positive number';
                  return null;
                },
              ),

              const SizedBox(height: 16),

              if (_needsProject)
                AsyncView<List<Project>>(
                  value: projects,
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _projectId,
                    decoration:
                        const InputDecoration(labelText: 'Project *'),
                    items: list
                        .map((p) => DropdownMenuItem(
                            value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _projectId = v),
                    validator: (v) =>
                        v == null ? 'Project is required' : null,
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
                  data: (list) {
                    // Filter suppliers by category for category-specific txn kinds.
                    // labour payments / labour-on-credit → labor suppliers only;
                    // material payments (TxnKind.supplierPay) and material buys →
                    // material suppliers only. Suppliers without a category fall
                    // through (legacy data).
                    final filtered = switch (_k) {
                      TxnKind.labourPayment ||
                      TxnKind.labourCredit =>
                        list
                            .where((s) =>
                                s.category == null ||
                                s.category == SupplierCategory.labor)
                            .toList(),
                      TxnKind.supplierPay || TxnKind.materialBuy => list
                          .where((s) =>
                              s.category == null ||
                              s.category == SupplierCategory.material)
                          .toList(),
                      _ => list,
                    };
                    if (filtered.isEmpty) {
                      return Text(
                        _k == TxnKind.labourPayment ||
                                _k == TxnKind.labourCredit
                            ? 'No labour-category suppliers. Add one in Suppliers.'
                            : 'No material-category suppliers. Add one in Suppliers.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      );
                    }
                    // Drop a stale selection that's no longer in the filtered list.
                    if (_supplierId != null &&
                        !filtered.any((s) => s.id == _supplierId)) {
                      _supplierId = null;
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: _supplierId,
                      decoration: InputDecoration(
                        labelText: _k == TxnKind.labourPayment ||
                                _k == TxnKind.labourCredit
                            ? 'Labour Provider *'
                            : 'Material Supplier *',
                      ),
                      items: filtered
                          .map((s) => DropdownMenuItem(
                              value: s.id, child: Text(s.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _supplierId = v),
                      validator: (v) =>
                          v == null ? 'Select a supplier' : null,
                    );
                  },
                ),
              ],

              if (_needsCashLike) ...[
                const SizedBox(height: 12),
                AsyncView<List<Account>>(
                  value: cashLike,
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return const Text(
                          'No banks/wallets defined. Add one from Settings.');
                    }
                    _cashLike ??= accounts.first;
                    return DropdownButtonFormField<Account>(
                      initialValue: _cashLike,
                      decoration: InputDecoration(
                        labelText: switch (_k) {
                          TxnKind.receiveFromProject => 'Receive Into',
                          TxnKind.serviceFee => 'Receive Into',
                          TxnKind.walletTransfer => 'From Wallet',
                          _ => 'Pay From',
                        },
                      ),
                      items: accounts
                          .map((a) => DropdownMenuItem(
                              value: a, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _cashLike = v ?? _cashLike),
                    );
                  },
                ),
              ],

              if (_isWalletTransfer) ...[
                const SizedBox(height: 12),
                AsyncView<List<Account>>(
                  value: cashLike,
                  data: (accounts) {
                    if (accounts.length < 2) {
                      return const Text(
                          'Add at least 2 banks/wallets to transfer between them.');
                    }
                    _transferTo ??= accounts.firstWhere(
                        (a) => a.id != _cashLike?.id,
                        orElse: () => accounts.first);
                    return DropdownButtonFormField<Account>(
                      initialValue: _transferTo,
                      decoration:
                          const InputDecoration(labelText: 'To Wallet'),
                      items: accounts
                          .map((a) => DropdownMenuItem(
                              value: a, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _transferTo = v ?? _transferTo),
                    );
                  },
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
                decoration: InputDecoration(
                  labelText: _isMaterialBuy
                      ? 'Memo (quantity, unit, etc.)'
                      : 'Description / Memo (optional)',
                ),
                maxLines: 3,
                minLines: 2,
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
        TxnKind.labourCredit => (
            dr: Accounts.labourCosts.name,
            cr: Accounts.supplierPayables.name
          ),
        TxnKind.supplierPay => (
            dr: Accounts.supplierPayables.name,
            cr: 'Cash / Bank'
          ),
        TxnKind.receiveFromProject => (
            dr: 'Cash / Bank',
            cr: Accounts.projectRevenue.name
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

/// Dropdown of every category in `material_types`, plus a "+ Manage…" trailing
/// button that jumps straight to the editor so the user can add a new type
/// without abandoning the in-progress purchase form.
///
/// The current selection is reported back through [onChanged]; when the
/// dropdown first loads with no selection, it auto-picks the first row so the
/// form is always submittable without an extra tap.
class _MaterialTypePicker extends ConsumerWidget {
  const _MaterialTypePicker({required this.current, required this.onChanged});

  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(materialTypesProvider);
    return typesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Could not load material types: $e'),
      data: (types) {
        if (types.isEmpty) {
          // Defensive: the migration seeds five built-ins, so this only fires
          // if a user manually deletes everything (which the repo prevents
          // for built-ins, but we keep a graceful path anyway).
          return _ManageRow(empty: true);
        }
        // Auto-select the first option once the list is available so the form
        // doesn't ship with an unselected dropdown.
        final selected =
            types.any((t) => t.name == current) ? current : types.first.name;
        if (selected != current) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onChanged(selected);
          });
        }
        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration:
                    const InputDecoration(labelText: 'Material Type *'),
                items: types
                    .map((t) => DropdownMenuItem(
                        value: t.name, child: Text(t.name)))
                    .toList(),
                onChanged: onChanged,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Pick a material type' : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Manage material types',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const MaterialTypesScreen()),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Live thousands-separator formatter for the amount input.
///
/// Reformats the visible text on every keystroke so the user sees
/// `1,234,567.89` while typing instead of a wall of digits. The decimal
/// portion (anything after the first `.`) is left untouched — only the
/// integer part gets grouped. Cursor position is preserved by counting
/// how many digits sit to the left of it before and after the rewrite.
///
/// We only need to recognise commas / dots as input characters because
/// the upstream `FilteringTextInputFormatter` already restricts the field
/// to `[0-9.,]`.
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    // Count digits to the left of the cursor in the raw input — used to
    // re-position the cursor in the formatted output without snapping it
    // to the end of the field.
    final cursor = newValue.selection.baseOffset.clamp(0, raw.length);
    var digitsBeforeCursor = 0;
    for (var i = 0; i < cursor; i++) {
      final ch = raw[i];
      if (ch != ',' && ch != '.') digitsBeforeCursor++;
    }

    // Only one decimal point allowed; everything after the first `.` is
    // the fractional part and is kept verbatim (no grouping).
    final stripped = raw.replaceAll(',', '');
    final dotIdx = stripped.indexOf('.');
    final intPart = dotIdx == -1 ? stripped : stripped.substring(0, dotIdx);
    final fracPart = dotIdx == -1 ? '' : stripped.substring(dotIdx);

    final grouped = _groupThousands(intPart);
    final formatted = '$grouped$fracPart';

    // Walk the formatted string left-to-right and stop once we've passed
    // the same number of digits we counted in the source — that's where
    // the cursor belongs.
    var newCursor = formatted.length;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      final ch = formatted[i];
      if (ch != ',' && ch != '.') seen++;
      if (seen == digitsBeforeCursor && dotIdx == -1
          ? seen == digitsBeforeCursor
          : false) {
        // unreached — explicit branch just below
      }
      if (seen >= digitsBeforeCursor) {
        newCursor = i + 1;
        break;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Inserts a comma every 3 digits from the right. Empty input returns
  /// empty so the field can be cleared without showing a stray comma.
  static String _groupThousands(String digits) {
    if (digits.isEmpty) return '';
    final buf = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      final fromRight = n - i;
      buf.write(digits[i]);
      if (fromRight > 1 && fromRight % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({this.empty = false});
  final bool empty;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            empty
                ? 'No material types defined. Add one to continue.'
                : 'Manage your material categories.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add type'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MaterialTypesScreen()),
          ),
        ),
      ],
    );
  }
}

