import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/project.dart';
import '../../data/repositories/entity_repository.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../providers/providers.dart';

/// Project archive workflow with strict reconciliation.
///
/// Both project models share the same gate now: the project's ledger net
/// (Material + Labour debits − Project Revenue − Service Fee Income) and
/// its outstanding Supplier Payables both have to be zero before
/// archive. The screen surfaces what's still off and offers the
/// service-fee reclassification button for Labour-Rate projects so the
/// user can do it in one tap before settling the cash side.
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
  ({double supplierPayables, double ledgerNet, double serviceFeeBooked})?
      _gate;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(ledgerRepoProvider.future);
    final rec = await repo.reconcileProject(widget.project.id);
    final outflow = await repo.projectOutflow(widget.project.id);
    final gate = await repo.projectArchiveStatus(widget.project.id);
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
      _gate = gate;
      _loading = false;
    });
  }

  /// Posts the labour-rate service fee (Dr Project Revenue / Cr Service
  /// Fee Income) without archiving. Lets the user do this as a discrete
  /// step so they can then settle the cash refund or collection
  /// separately and only archive once everything nets to zero.
  Future<void> _postServiceFee() async {
    final close = _close;
    if (close == null || close.serviceFee <= 0) return;
    setState(() => _busy = true);
    try {
      final ledgerRepo = await ref.read(ledgerRepoProvider.future);
      await ledgerRepo.postProjectServiceFee(
        projectId: widget.project.id,
        amount: close.serviceFee,
        description:
            'Service fee on close (${close.feePercent.toStringAsFixed(2)} %)',
      );
      bumpLedger(ref);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Service fee posted (${fmtMoney(close.serviceFee)}). Settle the remaining cash gap, then archive.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    setState(() => _busy = true);
    try {
      final entityRepo = await ref.read(entityRepoProvider.future);
      await entityRepo.archiveProject(
        widget.project.id,
        note: 'Archived after reconciliation',
      );
      bumpLedger(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Project archived (data preserved).')));
        Navigator.pop(context);
      }
    } on ProjectBudgetMismatchException catch (e) {
      // The customer paid less than budget. Offer to resize the contract
      // to match received before retrying the archive.
      if (!mounted) return;
      setState(() => _busy = false);
      await _handleBudgetMismatch(e);
    } on ReconciliationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Archive blocked — ${fmtSignedMoney(e.outstandingPayables)} of supplier payables still open.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleBudgetMismatch(
      ProjectBudgetMismatchException e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.compare_arrows,
            color: Theme.of(ctx).colorScheme.primary, size: 36),
        title: const Text('Customer paid less than budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original budget:  ${fmtMoney(e.budget)}'),
            const SizedBox(height: 4),
            Text('Total received:   ${fmtMoney(e.received)}'),
            const SizedBox(height: 4),
            Text('Shortfall:        ${fmtMoney(e.shortfall)}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BalanceColors.negative(context))),
            const SizedBox(height: 12),
            const Text(
                'To close this project, the contract value should match what '
                'was actually received. Resize the budget to ${"​"}'
                'the received amount and archive?'),
            const SizedBox(height: 8),
            Text(
                'If you expect more money to come in, cancel and record '
                'the remaining payment first.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Set budget to ${fmtMoney(e.received)}')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final entityRepo = await ref.read(entityRepoProvider.future);
      await entityRepo.updateProjectFields(
        widget.project.id,
        budget: e.received,
      );
      await entityRepo.archiveProject(
        widget.project.id,
        note: 'Budget resized to match received and archived',
      );
      bumpLedger(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Budget adjusted and project archived.')));
        Navigator.pop(context);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $err')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _rec == null || _outflow == null || _gate == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.project.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final p = widget.project;
    final rec = _rec!;
    final outflow = _outflow!;
    final gate = _gate!;
    final isLabour = p.model == ProjectModel.labourRate;

    final ledgerOk = gate.ledgerNet.abs() < 0.01;
    final payablesOk = gate.supplierPayables.abs() < 0.01;
    final canArchive = ledgerOk && payablesOk;

    final feeAlreadyPosted = (_close?.serviceFee ?? 0) > 0 &&
        gate.serviceFeeBooked >= (_close!.serviceFee - 0.01);

    return Scaffold(
      appBar: AppBar(title: Text('Reconcile · ${p.name}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _StatusBanner(
            ok: canArchive,
            ledgerNet: gate.ledgerNet,
            payables: gate.supplierPayables,
          ),
          const SizedBox(height: 8),
          _SectionTitle(title: 'Project Cashflows'),
          _Row(label: 'Received from Project', value: rec.projectInflow),
          _Row(label: 'Supplier Paid', value: rec.supplierPaid),
          _Row(
              label: 'Supplier Payables Outstanding',
              value: gate.supplierPayables,
              colorize: !payablesOk),
          _Row(label: 'Service Fee Booked', value: gate.serviceFeeBooked),
          _Row(
              label: 'Project Ledger Net',
              value: gate.ledgerNet,
              colorize: !ledgerOk),
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
              'With-Material model: archive only allowed once every cost is matched by an inflow and the supplier payable is zero.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),

          // Labour-Rate close has a two-step flow: post fee first, then
          // settle the cash gap, then archive. We show the fee button only
          // when the fee hasn't been booked yet.
          if (isLabour &&
              _close != null &&
              _close!.serviceFee > 0 &&
              !feeAlreadyPosted) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _postServiceFee,
              icon: const Icon(Icons.percent),
              label: Text(_busy
                  ? 'Working…'
                  : 'Post Service Fee (${fmtMoney(_close!.serviceFee)})'),
            ),
            const SizedBox(height: 8),
            Text(
              'Posts Dr Project Revenue / Cr Service Fee Income (non-cash). '
              'After this, settle the ${_close!.netToSettle >= 0 ? "refund to the customer" : "amount owed by the customer"} as a separate transaction so the ledger nets to zero.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],

          FilledButton.icon(
            onPressed: _busy || !canArchive ? null : _archive,
            icon: const Icon(Icons.archive),
            label: Text(_busy ? 'Archiving…' : 'Archive Project'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  canArchive ? null : Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            canArchive
                ? 'Books are settled — safe to archive. Data is preserved for legal evidence.'
                : 'Archive blocked. Settle the items shown in red above. '
                    'A project is closeable only when its ledger nets to zero AND no supplier payables for it remain open.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: canArchive ? null : BalanceColors.negative(context),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Pass/fail banner — primaryContainer when both gates are satisfied,
/// errorContainer otherwise. Spells out which side is off so the user
/// doesn't have to scan the rows.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.ok,
    required this.ledgerNet,
    required this.payables,
  });
  final bool ok;
  final double ledgerNet;
  final double payables;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: ok
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                color: ok
                    ? BalanceColors.positive(context)
                    : BalanceColors.negative(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ok
                    ? 'Reconciliation passes — safe to archive.'
                    : _failMessage(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _failMessage() {
    final pieces = <String>[
      if (ledgerNet.abs() >= 0.01)
        'ledger net ${fmtSignedMoney(ledgerNet)}',
      if (payables.abs() >= 0.01)
        'supplier payables ${fmtSignedMoney(payables)}',
    ];
    return 'Archive blocked: ${pieces.join(' and ')}. Settle these first.';
  }
}

/// Headline card for Labour-Rate close-out math. Shows what the customer
/// paid vs. what we spent, the computed fee, and the resulting refund or
/// amount-owed. Settling the difference is a separate manual step.
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
