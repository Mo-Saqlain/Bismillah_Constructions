import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../common/date_range_bar.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

class IncomeStatementScreen extends ConsumerStatefulWidget {
  const IncomeStatementScreen({super.key});

  @override
  ConsumerState<IncomeStatementScreen> createState() =>
      _IncomeStatementScreenState();
}

class _IncomeStatementScreenState
    extends ConsumerState<IncomeStatementScreen> {
  String? _projectId; // null = all projects
  DateTime? _from;
  DateTime? _to;

  /// Computes income statement figures respecting the two project models:
  ///
  /// With-Material: money received IS our revenue (capped at budget).
  ///   Any excess over budget = customer deposit we owe back.
  ///   Material and labour costs ARE our costs.
  ///
  /// Labour-Rate: money received is a CUSTOMER DEPOSIT (liability), not revenue.
  ///   Our revenue = service fee only (earned at project close).
  ///   Labour/material costs are the customer's costs funded by their deposit —
  ///   they should NOT appear on our P&L.
  ///   Customer deposit owed back = received − service-fee-reclassified − costs
  ///     paid on customer's behalf.
  Future<_ISFigures> _figures(WidgetRef ref) async {
    final repo = await ref.read(ledgerRepoProvider.future);
    final entityRepo = await ref.read(entityRepoProvider.future);

    // Load ALL projects (incl. archived) so closed jobs' figures are included.
    final allProjects = await entityRepo.projects(includeArchived: true);

    final scope = _projectId != null
        ? allProjects.where((p) => p.id == _projectId).toList()
        : allProjects;

    final lrProjects =
        scope.where((p) => p.model == ProjectModel.labourRate).toList();
    final wmProjects =
        scope.where((p) => p.model == ProjectModel.withMaterial).toList();

    // ── With-Material revenue (capped at budget per project) ─────────────────
    double wmRevenue = 0;
    double wmDeposit = 0;
    for (final proj in wmProjects) {
      final received = await repo.creditBalance(Accounts.projectRevenue.id,
          projectId: proj.id, from: _from, to: _to);
      final b = proj.budget;
      if (b != null && received > b) {
        wmRevenue += b;
        wmDeposit += received - b;
      } else {
        wmRevenue += received;
      }
    }

    // ── With-Material costs (OUR costs) ──────────────────────────────────────
    double matCosts = 0;
    double labCosts = 0;
    for (final proj in wmProjects) {
      matCosts += await repo.accountBalance(Accounts.materialCosts.id,
          projectId: proj.id, from: _from, to: _to);
      labCosts += await repo.accountBalance(Accounts.labourCosts.id,
          projectId: proj.id, from: _from, to: _to);
    }

    // ── Service fees (earned income across all project types) ─────────────────
    // When project-filtered to a specific project, only that project's fees.
    final serviceFees = await repo.creditBalance(Accounts.serviceFeeIncome.id,
        projectId: _projectId, from: _from, to: _to);

    // ── Personal draw (unlinked to projects) ─────────────────────────────────
    final draw = _projectId == null
        ? await repo.accountBalance(Accounts.personalDraw.id,
            from: _from, to: _to)
        : 0.0;

    // ── Labour-Rate customer deposit ──────────────────────────────────────────
    // Deposit still owed = (received − service-fee reclassified) − costs paid
    // on the customer's behalf (material + labour).
    // creditBalance(projectRevenue, LR) is already net of postProjectServiceFee
    // reclassification (Dr projectRevenue → Cr serviceFeeIncome).
    double lrDeposit = 0;
    for (final proj in lrProjects) {
      final projRev = await repo.creditBalance(Accounts.projectRevenue.id,
          projectId: proj.id, from: _from, to: _to);
      final labLR = await repo.accountBalance(Accounts.labourCosts.id,
          projectId: proj.id, from: _from, to: _to);
      final matLR = await repo.accountBalance(Accounts.materialCosts.id,
          projectId: proj.id, from: _from, to: _to);
      final net = projRev - labLR - matLR;
      if (net > 0) lrDeposit += net;
    }

    return _ISFigures(
      wmRevenue: wmRevenue,
      serviceFees: serviceFees,
      matCosts: matCosts,
      labCosts: labCosts,
      personalDraw: draw,
      lrDeposit: lrDeposit,
      wmDeposit: wmDeposit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    // re-trigger figures whenever ledger version, project filter or
    // date window changes.
    final version = ref.watch(ledgerVersionProvider);
    final figuresFuture = _figures(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Income Statement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DateRangeBar(
            from: _from,
            to: _to,
            onChanged: (f, t) => setState(() {
              _from = f;
              _to = t;
            }),
          ),
          const SizedBox(height: 12),
          AsyncView<List<Project>>(
            value: projects,
            data: (list) => DropdownButtonFormField<String?>(
              initialValue: _projectId,
              decoration: const InputDecoration(labelText: 'Filter by Project'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All projects')),
                ...list.map((p) => DropdownMenuItem<String?>(
                    value: p.id, child: Text(p.name))),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<_ISFigures>(
            key: ValueKey(
                '$_projectId-$version-${_from?.toIso8601String()}-${_to?.toIso8601String()}'),
            future: figuresFuture,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final f = snap.data!;
              final totalIncome = f.wmRevenue + f.serviceFees;
              final totalCosts = f.matCosts + f.labCosts + f.personalDraw;
              final net = totalIncome - totalCosts;
              final totalDeposit = f.lrDeposit + f.wmDeposit;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Period: ${formatPeriod(_from, _to)}',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Income ──────────────────────────────────────
                          if (f.wmRevenue > 0)
                            _row(context, 'Contract Revenue (With-Material)',
                                f.wmRevenue),
                          if (f.serviceFees > 0)
                            _row(context, 'Service Fees', f.serviceFees),
                          _row(context, 'Total Income', totalIncome,
                              bold: true),
                          const Divider(),
                          // ── Costs ────────────────────────────────────────
                          _row(context, 'Material Costs', -f.matCosts),
                          _row(context, 'Labour Costs', -f.labCosts),
                          if (f.personalDraw > 0)
                            _row(context, 'Personal Draw', -f.personalDraw),
                          _row(context, 'Total Costs', -totalCosts,
                              bold: true),
                          const Divider(),
                          _row(context, 'Net Profit / (Loss)', net,
                              bold: true,
                              color: net >= 0
                                  ? Colors.blue.shade700
                                  : Colors.red.shade700),
                          // ── Customer Deposits (informational) ───────────
                          if (totalDeposit > 0) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                  'Customer Deposits (owed back)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                          color: Colors.orange.shade700)),
                            ),
                            if (f.lrDeposit > 0)
                              _row(context, '  Labour-Rate projects',
                                  -f.lrDeposit,
                                  color: Colors.orange.shade700),
                            if (f.wmDeposit > 0)
                              _row(context, '  Over-budget (With-Material)',
                                  -f.wmDeposit,
                                  color: Colors.orange.shade700),
                            _row(context, '  Total deposits owed',
                                -totalDeposit,
                                bold: true, color: Colors.orange.shade700),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('PDF'),
                        onPressed: () async {
                          String? name;
                          if (_projectId != null) {
                            final repo =
                                await ref.read(entityRepoProvider.future);
                            name = (await repo.project(_projectId!))?.name;
                          }
                          await PdfGenerator.previewIncomeStatement(
                            IncomeStatementData(
                              projectName: name,
                              wmRevenue: f.wmRevenue,
                              serviceFees: f.serviceFees,
                              materialCosts: f.matCosts,
                              labourCosts: f.labCosts,
                              personalDraw: f.personalDraw,
                              lrDeposit: f.lrDeposit,
                              wmDeposit: f.wmDeposit,
                              generatedAt: DateTime.now(),
                              period: formatPeriod(_from, _to),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.file_download),
                        label: const Text('CSV'),
                        onPressed: () async {
                          String? name = 'All projects';
                          if (_projectId != null) {
                            final repo =
                                await ref.read(entityRepoProvider.future);
                            name =
                                (await repo.project(_projectId!))?.name ??
                                    name;
                          }
                          final csv = CsvExport.build(
                            headers: const ['Particulars', 'Amount'],
                            rows: [
                              ['Project:', name],
                              ['Period:', formatPeriod(_from, _to)],
                              ['', ''],
                              if (f.wmRevenue > 0)
                                ['Contract Revenue (With-Material)',
                                    f.wmRevenue.toStringAsFixed(2)],
                              if (f.serviceFees > 0)
                                ['Service Fees',
                                    f.serviceFees.toStringAsFixed(2)],
                              ['Total Income', totalIncome.toStringAsFixed(2)],
                              ['', ''],
                              ['Material Costs',
                                  (-f.matCosts).toStringAsFixed(2)],
                              ['Labour Costs',
                                  (-f.labCosts).toStringAsFixed(2)],
                              if (f.personalDraw > 0)
                                ['Personal Draw',
                                    (-f.personalDraw).toStringAsFixed(2)],
                              ['Total Costs',
                                  (-totalCosts).toStringAsFixed(2)],
                              ['Net Profit / (Loss)',
                                  net.toStringAsFixed(2)],
                              if (f.lrDeposit + f.wmDeposit > 0) ...[
                                ['', ''],
                                ['-- Customer Deposits (owed back) --', ''],
                                if (f.lrDeposit > 0)
                                  ['  Labour-Rate projects',
                                      (-f.lrDeposit).toStringAsFixed(2)],
                                if (f.wmDeposit > 0)
                                  ['  Over-budget (With-Material)',
                                      (-f.wmDeposit).toStringAsFixed(2)],
                                ['  Total deposits owed',
                                    (-(f.lrDeposit + f.wmDeposit))
                                        .toStringAsFixed(2)],
                              ],
                            ],
                          );
                          await CsvExport.share(
                            fileName:
                                'income_statement_${DateTime.now().millisecondsSinceEpoch}',
                            csv: csv,
                            subject: 'Income Statement — $name',
                          );
                        },
                      ),
                    ),
                  ]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext ctx, String label, double v,
      {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      color: color,
      fontSize: 16,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(fmtSignedMoney(v), style: style),
        ],
      ),
    );
  }
}

class _ISFigures {
  final double wmRevenue;
  final double serviceFees;
  final double matCosts;
  final double labCosts;
  final double personalDraw;
  /// Net customer deposit owed back from Labour-Rate projects.
  final double lrDeposit;
  /// Excess received over budget from With-Material projects.
  final double wmDeposit;

  const _ISFigures({
    required this.wmRevenue,
    required this.serviceFees,
    required this.matCosts,
    required this.labCosts,
    required this.personalDraw,
    required this.lrDeposit,
    required this.wmDeposit,
  });
}
