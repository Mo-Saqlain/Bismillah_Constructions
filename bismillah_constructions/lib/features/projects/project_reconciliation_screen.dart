import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/project.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../providers/providers.dart';

/// Project archive workflow with reconciliation check.
///
/// With-Material projects: blocks archive while supplier payables remain
/// outstanding (`customer_inflow == supplier_paid + supplier_payables`).
///
/// Labour-Rate projects: shows the close-out math (customer paid vs.
/// money spent on their behalf, the contractor's service fee, and the
/// resulting refund-to-customer or amount-owed-by-customer). On archive
/// the service fee is posted automatically as a non-cash reclassification
/// (Dr Project Revenue / Cr Service Fee Income), so the books separate
/// "money handled for the customer" from "earnings".
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
  LabourRateClose? _close;
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
    LabourRateClose? close;
    if (widget.project.model == ProjectModel.labourRate) {
      close = await repo.labourRateCloseSummary(
        widget.project.id,
        widget.project.serviceFeePercent ?? 0,
      );
    }
    if (!mounted) return;
    setState(() {
      _rec = rec;
      _outflow = outflow;
      _close = close;
      _loading = false;
    });
  }

  /// Archives the project. For Labour-Rate projects with a non-zero
  /// service fee, also posts the fee as a non-cash reclassification
  /// before archiving so the close-out is recorded in the ledger.
  Future<void> _archive() async {
    setState(() => _archiving = true);
    try {
      final ledgerRepo = await ref.read(ledgerRepoProvider.future);
      final entityRepo = await ref.read(entityRepoProvider.future);

      final close = _close;
      if (close != null && close.serviceFee > 0) {
        await ledgerRepo.postProjectServiceFee(
          projectId: widget.project.id,
          amount: close.serviceFee,
          description:
              'Service fee on close (${close.feePercent.toStringAsFixed(2)} %)',
        );
      }

      await entityRepo.archiveProject(
        widget.project.id,
        note: close == null
            ? 'Archived after reconciliation review'
            : 'Archived (Labour-Rate close: fee ${fmtMoney(close.serviceFee)}, '
                'settlement ${fmtSignedMoney(close.netToSettle)})',
      );
      bumpLedger(ref);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(close != null && close.serviceFee > 0
                ? 'Service fee posted and project archived.'
                : 'Project archived (data preserved).')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
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
    final isLabour = p.model == ProjectModel.labourRate;

    return Scaffold(
      appBar: AppBar(title: Text('Reconcile · ${p.name}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _StatusBanner(balanced: balanced, payables: rec.supplierPayables),
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
          if (isLabour && _close != null)
            _LabourRateCloseCard(close: _close!)
          else if (isLabour)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'No service fee % is set on this project. Edit the project to set one before archiving.'),
            )
          else
            _Row(
                label: 'Business Savings (Customer Inflow − Outflow)',
                value: rec.projectInflow - outflow,
                colorize: true),
          if (!isLabour) ...[
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
            final close = _close;
            final btnLabel = _archiving
                ? 'Working…'
                : (isLabour && close != null && close.serviceFee > 0
                    ? 'Post Service Fee & Archive'
                    : 'Archive Project');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed:
                      _archiving || blockArchive ? null : _archive,
                  icon: Icon(isLabour && close != null && close.serviceFee > 0
                      ? Icons.percent
                      : Icons.archive),
                  label: Text(btnLabel),
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
                      : (isLabour && close != null && close.serviceFee > 0
                          ? 'On confirm, the service fee will be posted '
                              '(Dr Project Revenue / Cr Service Fee Income, '
                              'non-cash) and the project archived. The '
                              '${close.netToSettle >= 0 ? "refund" : "amount owed by customer"} '
                              'still has to be recorded as a separate '
                              'transaction when cash actually changes hands.'
                          : 'Archiving sets is_archived=True. Data is preserved for legal evidence.'),
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

/// Pass/fail banner at the top of the screen — same colour rules as the
/// rest of the app (primaryContainer for OK, errorContainer for blocked).
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.balanced, required this.payables});
  final bool balanced;
  final double payables;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: balanced
          ? Theme.of(context).colorScheme.primaryContainer
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
                    : 'Outstanding payables: ${fmtSignedMoney(payables)}. Settle before archiving.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Headline card for Labour-Rate close-out math.
///
/// Shows what the customer paid vs. what we spent on their behalf, the
/// computed fee, and the resulting refund or amount-owed. Settling the
/// difference is a separate manual step (cash actually moving) — this
/// card is purely informational + drives the auto-fee post on archive.
class _LabourRateCloseCard extends StatelessWidget {
  const _LabourRateCloseCard({required this.close});
  final LabourRateClose close;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settle = close.netToSettle;
    final surplus = settle >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(label: 'Customer Paid (Inflow)', value: close.customerPaid),
          _Row(label: 'Spent on Customer\'s Behalf', value: close.totalSpent),
          _Row(
              label: 'Service Fee % configured',
              value: close.feePercent,
              suffix: '%'),
          _Row(label: 'Service Fee Amount', value: close.serviceFee),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surplus ? scheme.primaryContainer : scheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  surplus ? Icons.south_west : Icons.north_east,
                  color: surplus
                      ? BalanceColors.positive(context)
                      : BalanceColors.negative(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        surplus ? 'Refund to Customer' : 'Customer Owes You',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        surplus
                            ? '${fmtMoney(close.refundToCustomer)} — surplus '
                                'after service fee. Record this as a separate '
                                'cash-out transaction when refunded.'
                            : '${fmtMoney(close.customerOwesUs)} — covers the '
                                'spending shortfall plus the service fee. '
                                'Record this as Receive From Project (deficit) '
                                'and a separate fee receipt when collected.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
