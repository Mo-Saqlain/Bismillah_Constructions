import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import 'csv_export.dart';

/// Project Profitability Summary — one row per project with the
/// bottom-line numbers an owner cares about: revenue received, money
/// spent, and the resulting net position.
///
/// For With-Material projects, "Net" is `received − spent` (savings).
/// For Labour-Rate projects, "Net" is the booked Service Fee Income for
/// that project (the contractor's earnings; the rest is pass-through).
///
/// Sorted by profitability descending so the most lucrative job is on
/// top. Toggles between active and archived projects.
class ProjectProfitabilityScreen extends ConsumerStatefulWidget {
  const ProjectProfitabilityScreen({super.key});

  @override
  ConsumerState<ProjectProfitabilityScreen> createState() =>
      _ProjectProfitabilityScreenState();
}

class _ProjectProfitabilityScreenState
    extends ConsumerState<ProjectProfitabilityScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(_profitabilityProvider(_showArchived));
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived
            ? 'Closed Project Profitability'
            : 'Project Profitability'),
        actions: [
          IconButton(
            tooltip: _showArchived
                ? 'Show active projects'
                : 'View closed projects',
            icon: Icon(_showArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.file_download, size: 26),
            onPressed: () async {
              final list = await ref
                  .read(_profitabilityProvider(_showArchived).future);
              await _exportCsv(list);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncView<List<_ProfitabilityRow>>(
        value: dataAsync,
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_showArchived
                    ? 'No closed projects yet.'
                    : 'No active projects yet.'),
              ),
            );
          }
          final grandRevenue =
              rows.fold<double>(0, (a, r) => a + r.revenue);
          final grandSpent = rows.fold<double>(0, (a, r) => a + r.spent);
          final grandNet = rows.fold<double>(0, (a, r) => a + r.net);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _SummaryCard(
                projects: rows.length,
                revenue: grandRevenue,
                spent: grandSpent,
                net: grandNet,
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Project')),
                      DataColumn(label: Text('Model')),
                      DataColumn(label: Text('Received'), numeric: true),
                      DataColumn(label: Text('Spent'), numeric: true),
                      DataColumn(label: Text('Net'), numeric: true),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(cells: [
                          DataCell(Text(r.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                          DataCell(Text(r.model.label,
                              style: const TextStyle(fontSize: 12))),
                          DataCell(Text(fmtMoney(r.revenue))),
                          DataCell(Text(fmtMoney(r.spent))),
                          DataCell(Text(fmtSignedMoney(r.net),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: BalanceColors.signed(context, r.net)))),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Net = received − spent for With-Material projects, '
                'and the booked service-fee income for Labour-Rate projects '
                '(the contractor\'s earnings — the rest is customer money '
                'passing through).',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportCsv(List<_ProfitabilityRow> rows) async {
    final csv = CsvExport.build(
      headers: const ['Project', 'Model', 'Received', 'Spent', 'Net'],
      rows: [
        for (final r in rows)
          [
            r.name,
            r.model.label,
            r.revenue.toStringAsFixed(2),
            r.spent.toStringAsFixed(2),
            r.net.toStringAsFixed(2),
          ],
      ],
    );
    await CsvExport.share(
      fileName:
          'project_profitability_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Project Profitability Summary',
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.projects,
    required this.revenue,
    required this.spent,
    required this.net,
  });
  final int projects;
  final double revenue;
  final double spent;
  final double net;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$projects project${projects == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(fmtSignedMoney(net),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BalanceColors.signed(context, net),
                    )),
            Text('Total net result',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(label: 'Received', value: revenue),
                _Stat(label: 'Spent', value: spent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(fmtMoney(value),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ProfitabilityRow {
  final String id;
  final String name;
  final ProjectModel model;
  final double revenue;
  final double spent;
  final double net;
  const _ProfitabilityRow({
    required this.id,
    required this.name,
    required this.model,
    required this.revenue,
    required this.spent,
    required this.net,
  });
}

/// Pulls every project (active or archived per [archived]) and asks the
/// ledger for the cost / revenue / fee-income aggregates per project,
/// then computes a single Net per row depending on the project model.
final _profitabilityProvider =
    FutureProvider.family<List<_ProfitabilityRow>, bool>((ref, archived) async {
  ref.watch(ledgerVersionProvider);
  final entityRepo = await ref.watch(entityRepoProvider.future);
  final ledger = await ref.watch(ledgerRepoProvider.future);

  final projects = archived
      ? await entityRepo.archivedProjects()
      : await entityRepo.projects(activeOnly: true);

  final rows = <_ProfitabilityRow>[];
  for (final p in projects) {
    final spent = await ledger.projectOutflow(p.id);
    final revenue = await ledger.sumCredits(Accounts.projectRevenue.id,
        projectId: p.id);
    final feeIncome = await ledger.sumCredits(Accounts.serviceFeeIncome.id,
        projectId: p.id);

    // Net for the contractor:
    //   * With-Material: cash kept after spending = received − spent.
    //   * Labour-Rate: pass-through, profit = booked service fee.
    final net = p.model == ProjectModel.labourRate
        ? feeIncome
        : revenue - spent;

    rows.add(_ProfitabilityRow(
      id: p.id,
      name: p.name,
      model: p.model,
      revenue: revenue,
      spent: spent,
      net: net,
    ));
  }
  rows.sort((a, b) => b.net.compareTo(a.net));
  return rows;
});
