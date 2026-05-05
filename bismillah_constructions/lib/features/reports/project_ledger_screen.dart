import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import 'csv_export.dart';

/// Project ledger — every journal entry recorded against a specific project,
/// with a running balance (debits − credits). Replaces the old per-customer
/// ledger now that customers are gone.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final entriesAsync = ref.watch(_projectEntriesProvider(project.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Ledger · ${project.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: () async {
              final entries =
                  await ref.read(_projectEntriesProvider(project.id).future);
              await _exportCsv(project, entries);
            },
          ),
        ],
      ),
      body: AsyncView<List<JournalEntry>>(
        value: entriesAsync,
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No transactions for this project yet.'),
            ));
          }
          // Group rows by transaction_id and present one card per transaction
          // with a running net (debits to project − credits from project).
          final pairs = <String, List<JournalEntry>>{};
          for (final e in entries) {
            (pairs[e.transactionId] ??= []).add(e);
          }
          var running = 0.0;
          final cards = <Widget>[];
          for (final txnId in pairs.keys) {
            final pair = pairs[txnId]!;
            if (pair.length != 2) continue;
            final dr = pair.firstWhere((e) => e.debit > 0);
            final cr = pair.firstWhere((e) => e.credit > 0);
            // Sign: positive = money INTO project (revenue + receivables) /
            // negative = money OUT of project (costs).
            final signed = dr.debit - dr.credit; // dr row is the spend side
            running += signed;
            cards.add(_TxnCard(
              dr: dr,
              cr: cr,
              running: running,
            ));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: cards.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i == 0) return _Header(project: project, total: running);
              return cards[i - 1];
            },
          );
        },
      ),
    );
  }

  Future<void> _exportCsv(Project p, List<JournalEntry> entries) async {
    final pairs = <String, List<JournalEntry>>{};
    for (final e in entries) {
      (pairs[e.transactionId] ??= []).add(e);
    }
    var running = 0.0;
    final rows = <List<Object?>>[];
    for (final txnId in pairs.keys) {
      final pair = pairs[txnId]!;
      if (pair.length != 2) continue;
      final dr = pair.firstWhere((e) => e.debit > 0);
      final cr = pair.firstWhere((e) => e.credit > 0);
      running += (dr.debit - dr.credit);
      rows.add([
        fmtDate(dr.createdAt),
        Accounts.byId(dr.accountId).name,
        Accounts.byId(cr.accountId).name,
        dr.debit.toStringAsFixed(2),
        running.toStringAsFixed(2),
        dr.description ?? '',
      ]);
    }
    final csv = CsvExport.build(
      headers: ['Date', 'Debit', 'Credit', 'Amount', 'Running', 'Memo'],
      rows: rows,
    );
    await CsvExport.share(
      fileName: 'project_ledger_${p.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Project Ledger — ${p.name}',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project, required this.total});
  final Project project;
  final double total;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${project.model.label}'
                '${project.clientName != null ? ' · ${project.clientName}' : ''}'),
            const SizedBox(height: 4),
            Text('Net debit position (cost side): ${fmtSignedMoney(total)}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BalanceColors.signed(context, -total))),
          ],
        ),
      ),
    );
  }
}

class _TxnCard extends StatelessWidget {
  const _TxnCard({required this.dr, required this.cr, required this.running});
  final JournalEntry dr;
  final JournalEntry cr;
  final double running;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fmtMoney(dr.debit),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                Text(fmtDate(dr.createdAt),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Text('Dr  ${Accounts.byId(dr.accountId).name}'),
            Text('     Cr  ${Accounts.byId(cr.accountId).name}'),
            if (dr.description != null && dr.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(dr.description!,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 4),
            Text('Running: ${fmtSignedMoney(running)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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
