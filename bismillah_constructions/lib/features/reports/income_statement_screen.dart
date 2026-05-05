import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
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

  Future<({double rev, double mat, double lab})> _figures(WidgetRef ref) async {
    final repo = await ref.read(ledgerRepoProvider.future);
    final rev =
        await repo.creditBalance(Accounts.projectRevenue.id, projectId: _projectId);
    final mat =
        await repo.accountBalance(Accounts.materialCosts.id, projectId: _projectId);
    final lab =
        await repo.accountBalance(Accounts.labourCosts.id, projectId: _projectId);
    return (rev: rev, mat: mat, lab: lab);
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    // re-trigger figures whenever ledger version or project filter changes
    final version = ref.watch(ledgerVersionProvider);
    final figuresFuture = _figures(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Income Statement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          FutureBuilder<({double rev, double mat, double lab})>(
            key: ValueKey('$_projectId-$version'),
            future: figuresFuture,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final f = snap.data!;
              final net = f.rev - (f.mat + f.lab);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _row(context, 'Revenue', f.rev, bold: true),
                          const Divider(),
                          _row(context, 'Material Costs', -f.mat),
                          _row(context, 'Labour Costs', -f.lab),
                          _row(context, 'Total Costs', -(f.mat + f.lab),
                              bold: true),
                          const Divider(),
                          _row(context, 'Net Profit / (Loss)', net,
                              bold: true,
                              color: net >= 0
                                  ? Colors.green.shade700
                                  : Colors.red.shade700),
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
                              revenue: f.rev,
                              materialCosts: f.mat,
                              labourCosts: f.lab,
                              generatedAt: DateTime.now(),
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
                            headers: ['Line', 'Amount'],
                            rows: [
                              ['Revenue', f.rev.toStringAsFixed(2)],
                              ['Material Costs', (-f.mat).toStringAsFixed(2)],
                              ['Labour Costs', (-f.lab).toStringAsFixed(2)],
                              ['Total Costs',
                                  (-(f.mat + f.lab)).toStringAsFixed(2)],
                              ['Net Profit / (Loss)', net.toStringAsFixed(2)],
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
