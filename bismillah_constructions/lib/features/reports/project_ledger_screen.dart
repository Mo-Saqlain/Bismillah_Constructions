import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../common/ledger_view.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

/// Project ledger — every journal entry recorded against a specific project,
/// rendered as the same five-column ledger table used by the supplier and
/// bank/wallet screens.
class ProjectLedgerPickerScreen extends ConsumerWidget {
  const ProjectLedgerPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Project Ledger')),
      body: AsyncView<List<Project>>(
        value: projects,
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Define a project to see its ledger.'),
            ));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = list[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.foundation)),
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p.model.label}'
                      '${p.clientName != null ? ' · ${p.clientName}' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectLedgerScreen(project: p),
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
}

class ProjectLedgerScreen extends ConsumerWidget {
  const ProjectLedgerScreen({super.key, required this.project});
  final Project project;

  /// Each two-row balanced transaction collapses into one ledger row whose
  /// debit-side entry holds the date/memo and is signed: positive = money
  /// flowing INTO project costs, the running total is the cumulative
  /// project spend (cost side).
  List<LedgerRow> _toRows(List<JournalEntry> entries) {
    final byTxn = <String, List<JournalEntry>>{};
    for (final e in entries) {
      (byTxn[e.transactionId] ??= []).add(e);
    }
    double running = 0;
    final out = <LedgerRow>[];
    for (final pair in byTxn.values) {
      if (pair.length != 2) continue;
      final dr = pair.firstWhere((e) => e.debit > 0,
          orElse: () => pair.first);
      running += dr.debit - dr.credit;
      final memo = (dr.description?.isNotEmpty ?? false)
          ? dr.description!
          : Accounts.byId(dr.accountId).name;
      out.add(LedgerRow(
        date: dr.createdAt,
        memo: memo,
        debit: dr.debit,
        credit: dr.credit,
        balance: running,
      ));
    }
    return out;
  }

  Future<void> _exportPdf(List<JournalEntry> entries) async {
    await PdfGenerator.previewProjectLedger(ProjectLedgerData(
      projectName: project.name,
      rows: entries,
      generatedAt: DateTime.now(),
    ));
  }

  Future<void> _exportCsv(List<JournalEntry> entries) async {
    final rows = _toRows(entries);
    final csv = CsvExport.build(
      headers: ['Date', 'Memo', 'Debit', 'Credit', 'Running'],
      rows: rows
          .map((r) => [
                fmtDate(r.date),
                r.memo,
                r.debit > 0 ? r.debit.toStringAsFixed(2) : '',
                r.credit > 0 ? r.credit.toStringAsFixed(2) : '',
                r.balance.toStringAsFixed(2),
              ])
          .toList(),
    );
    await CsvExport.share(
      fileName:
          'project_ledger_${project.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Project Ledger — ${project.name}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final entriesAsync = ref.watch(_projectEntriesProvider(project.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Ledger · ${project.name}'),
        actions: [
          LedgerExportActions(
            enabled: entriesAsync.hasValue &&
                (entriesAsync.value?.isNotEmpty ?? false),
            onExportPdf: () async {
              final e = await ref
                  .read(_projectEntriesProvider(project.id).future);
              await _exportPdf(e);
            },
            onExportCsv: () async {
              final e = await ref
                  .read(_projectEntriesProvider(project.id).future);
              await _exportCsv(e);
            },
          ),
        ],
      ),
      body: AsyncView<List<JournalEntry>>(
        value: entriesAsync,
        data: (entries) {
          final rows = _toRows(entries);
          final total = rows.isEmpty ? 0.0 : rows.last.balance;
          return LedgerView(
            title: project.name,
            subtitle: '${project.model.label}'
                '${project.clientName != null ? ' · ${project.clientName}' : ''}',
            rows: rows,
            totalLabel: 'Net Cost-Side Position',
            totalValue: total,
            signedTotal: true,
            emptyMessage: 'No transactions for this project yet.',
          );
        },
      ),
    );
  }
}

final _projectEntriesProvider =
    FutureProvider.family<List<JournalEntry>, String>((ref, projectId) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.entriesForProject(projectId);
});
