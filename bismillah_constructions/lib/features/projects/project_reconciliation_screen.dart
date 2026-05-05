import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/project.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../providers/providers.dart';

/// Project archive workflow with reconciliation check (spec section 1).
///
/// Validates: customer_inflow == supplier_paid + supplier_payables.
/// Also shows profit summary based on the project's model (With-Material vs.
/// Labour-Rate, spec section 2).
class ProjectReconciliationScreen extends ConsumerStatefulWidget {
  const ProjectReconciliationScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectReconciliationScreen> createState() =>
      _ProjectReconciliationScreenState();
}

class _ProjectReconciliationScreenState
    extends ConsumerState<ProjectReconciliationScreen> {
  ProjectReconciliation? _rec;
  double? _outflow;
  bool _loading = true;
  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(ledgerRepoProvider.future);
    final rec = await repo.reconcileProject(widget.project.id);
    final outflow = await repo.projectOutflow(widget.project.id);
    if (!mounted) return;
    setState(() {
      _rec = rec;
      _outflow = outflow;
      _loading = false;
    });
  }

  Future<void> _archive() async {
    setState(() => _archiving = true);
    try {
      final repo = await ref.read(entityRepoProvider.future);
      await repo.archiveProject(widget.project.id,
          note: 'Archived after reconciliation review');
      bumpLedger(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project archived (data preserved)')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _rec == null || _outflow == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.project.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final p = widget.project;
    final rec = _rec!;
    final outflow = _outflow!;
    final balanced = rec.isBalanced;

    // Profit per spec section 2.
    final isLabour = p.model == ProjectModel.labourRate;
    final feePct = p.serviceFeePercent ?? 0;
    final serviceFee = isLabour ? outflow * feePct / 100 : 0.0;
    final businessSavings = isLabour ? 0.0 : (rec.projectInflow - outflow);

    return Scaffold(
      appBar: AppBar(title: Text('Reconcile · ${p.name}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: balanced
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(balanced ? Icons.check_circle : Icons.error_outline,
                      color: balanced
                          ? BalanceColors.positive(context)
                          : BalanceColors.negative(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      balanced
                          ? 'Reconciliation passes — safe to archive.'
                          : 'Outstanding payables: ${fmtSignedMoney(rec.supplierPayables)}. Settle before archiving.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SectionTitle(title: 'Project Cashflows'),
          _Row(label: 'Received from Project', value: rec.projectInflow),
          _Row(label: 'Supplier Paid', value: rec.supplierPaid),
          _Row(
              label: 'Supplier Payables Outstanding',
              value: rec.supplierPayables,
              colorize: rec.supplierPayables != 0),
          _Row(
              label: 'Net (Inflow − Costs)',
              value: rec.savings,
              colorize: true),
          const SizedBox(height: 12),
          _SectionTitle(title: 'Profit (${p.model.label})'),
          _Row(label: 'Total Project Outflow', value: outflow),
          if (isLabour) ...[
            _Row(
                label: 'Service Fee % configured',
                value: feePct,
                suffix: '%'),
            _Row(
                label: 'Computed Service Fee',
                value: serviceFee,
                colorize: true),
            const SizedBox(height: 4),
            Text(
              'Labour-Rate model: business is a pass-through (Balance = 0). Profit = service fee.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            _Row(
                label: 'Business Savings (Customer Inflow − Outflow)',
                value: businessSavings,
                colorize: true),
            const SizedBox(height: 4),
            Text(
              'With-Material model: remaining balance at archive = Business Savings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          // With-Material projects require strict reconciliation:
          //   Customer_Inflow == Supplier_Paid + Supplier_Payables
          // Labour-Rate projects are pass-through, so the equation may legitimately
          // not balance and we don't block the archive.
          Builder(builder: (_) {
            final blockArchive = !isLabour && !balanced;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed:
                      _archiving || blockArchive ? null : _archive,
                  icon: const Icon(Icons.archive),
                  label: Text(_archiving ? 'Archiving…' : 'Archive Project'),
                  style: FilledButton.styleFrom(
                    backgroundColor: blockArchive
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  blockArchive
                      ? 'With-Material project: archive blocked while '
                          '${fmtSignedMoney(rec.supplierPayables)} of supplier '
                          'payables are still open. Settle them first.'
                      : 'Archiving sets is_archived=True. Data is preserved for legal evidence (spec section 3).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: blockArchive
                            ? BalanceColors.negative(context)
                            : null,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.suffix,
    this.colorize = false,
  });
  final String label;
  final double value;
  final String? suffix;
  final bool colorize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: FontWeight.w600,
      color: colorize ? BalanceColors.signed(context, value) : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(suffix == '%' ? '${value.toStringAsFixed(2)} %' : fmtSignedMoney(value),
              style: style),
        ],
      ),
    );
  }
}
