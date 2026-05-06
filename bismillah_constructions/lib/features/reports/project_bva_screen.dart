import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/project.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../providers/providers.dart';
import 'csv_export.dart';

/// Budget vs Actual per project, broken down by category.
///
/// Categories: each material type purchased + an "Other Material" residual
/// for material costs posted directly to the journal without an inventory row,
/// plus Labour. The project's `budget` field is the BoQ estimate.
class ProjectBvaScreen extends ConsumerWidget {
  const ProjectBvaScreen({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final dataAsync = ref.watch(_bvaProvider(project.id));
    final budget = project.budget ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('BvA · ${project.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: () async {
              final bva = await ref.read(_bvaProvider(project.id).future);
              await _exportCsv(project, bva, budget);
            },
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bva) {
          final spend = bva.totalSpend;
          final remaining = budget - spend;
          final pct = budget > 0 ? (spend / budget * 100) : 0.0;
          final overrun = budget > 0 && spend > budget;

          final categories = <(String, double)>[
            for (final e in bva.materialByType.entries)
              ('Material · ${e.key}', e.value),
            if (bva.otherMaterial > 0)
              ('Material · Other', bva.otherMaterial),
            ('Labour', bva.labour),
          ];

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                color: overrun
                    ? Theme.of(context).colorScheme.errorContainer
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Budget'),
                            Text(fmtMoney(budget),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ]),
                      const SizedBox(height: 4),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Actual Spend'),
                            Text(fmtMoney(spend),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: overrun
                                        ? BalanceColors.negative(context)
                                        : null)),
                          ]),
                      const SizedBox(height: 4),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(remaining >= 0
                                ? 'Remaining'
                                : 'Over Budget'),
                            Text(fmtSignedMoney(remaining),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: BalanceColors.signed(
                                        context, remaining))),
                          ]),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: budget == 0
                            ? null
                            : (spend / budget).clamp(0, 1.0).toDouble(),
                        minHeight: 8,
                        color: overrun
                            ? BalanceColors.negative(context)
                            : BalanceColors.positive(context),
                      ),
                      const SizedBox(height: 4),
                      Text(budget == 0
                          ? 'No budget set on this project.'
                          : '${pct.toStringAsFixed(1)} % of budget consumed'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Actual'), numeric: true),
                      DataColumn(label: Text('% of spend'), numeric: true),
                    ],
                    rows: [
                      for (final c in categories)
                        DataRow(cells: [
                          DataCell(Text(c.$1)),
                          DataCell(Text(fmtMoney(c.$2))),
                          DataCell(Text(spend == 0
                              ? '—'
                              : '${(c.$2 / spend * 100).toStringAsFixed(1)} %')),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Material costs are split using `material_inventory` rows. Costs '
                'posted directly without an inventory row appear under '
                '"Material · Other".',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportCsv(Project p, ProjectBva bva, double budget) async {
    final spend = bva.totalSpend;
    final csv = CsvExport.build(
      headers: ['Category', 'Actual', 'Pct of Spend'],
      rows: [
        for (final e in bva.materialByType.entries)
          [
            'Material · ${e.key}',
            e.value.toStringAsFixed(2),
            spend == 0 ? '0' : (e.value / spend * 100).toStringAsFixed(1),
          ],
        if (bva.otherMaterial > 0)
          [
            'Material · Other',
            bva.otherMaterial.toStringAsFixed(2),
            spend == 0
                ? '0'
                : (bva.otherMaterial / spend * 100).toStringAsFixed(1),
          ],
        [
          'Labour',
          bva.labour.toStringAsFixed(2),
          spend == 0 ? '0' : (bva.labour / spend * 100).toStringAsFixed(1),
        ],
        ['', '', ''],
        ['Budget', budget.toStringAsFixed(2), ''],
        ['Total Spend', spend.toStringAsFixed(2), ''],
        ['Remaining', (budget - spend).toStringAsFixed(2), ''],
      ],
    );
    await CsvExport.share(
      fileName: 'bva_${p.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Budget vs Actual — ${p.name}',
    );
  }
}

final _bvaProvider =
    FutureProvider.family<ProjectBva, String>((ref, projectId) async {
  ref.watch(ledgerVersionProvider);
  final ledger = await ref.watch(ledgerRepoProvider.future);
  return ledger.projectBva(projectId);
});
