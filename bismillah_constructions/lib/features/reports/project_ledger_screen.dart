import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/project.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../common/date_range_bar.dart';
import '../common/ledger_view.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

/// Project ledger — every journal entry recorded against a specific project,
/// rendered as the same five-column ledger table used by the supplier and
/// bank/wallet screens. The picker has a toggle so the user can also browse
/// the ledgers of archived (closed) projects without unarchiving them.
class ProjectLedgerPickerScreen extends ConsumerStatefulWidget {
  const ProjectLedgerPickerScreen({super.key});

  @override
  ConsumerState<ProjectLedgerPickerScreen> createState() =>
      _ProjectLedgerPickerScreenState();
}

class _ProjectLedgerPickerScreenState
    extends ConsumerState<ProjectLedgerPickerScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final projects = _showArchived
        ? ref.watch(archivedProjectsProvider)
        : ref.watch(activeProjectsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived
            ? 'Closed Projects · Ledger'
            : 'Project Ledger'),
        actions: [
          IconButton(
            tooltip: _showArchived
                ? 'Show active projects'
                : 'View closed projects',
            icon: Icon(
                _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            onPressed: () =>
                setState(() => _showArchived = !_showArchived),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncView<List<Project>>(
        value: projects,
        data: (list) {
          if (list.isEmpty) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_showArchived
                  ? 'No closed projects yet.'
                  : 'Define a project to see its ledger.'),
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
                  leading: CircleAvatar(
                      child: Icon(_showArchived
                          ? Icons.archive
                          : Icons.foundation)),
                  title: Text(p.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: _showArchived
                              ? TextDecoration.lineThrough
                              : null)),
                  subtitle: Text('${p.model.label}'
                      '${p.clientName != null ? ' · ${p.clientName}' : ''}'
                      '${_showArchived ? ' · ARCHIVED' : ''}'),
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

class ProjectLedgerScreen extends ConsumerStatefulWidget {
  const ProjectLedgerScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectLedgerScreen> createState() =>
      _ProjectLedgerScreenState();
}

class _ProjectLedgerScreenState extends ConsumerState<ProjectLedgerScreen> {
  DateTime? _from;
  DateTime? _to;

  /// Each row in `entries` is already the project-attributable leg
  /// (Material/Labour Costs as a debit, Project Revenue / Service Fee as
  /// a credit). We render them in order and accumulate the running net
  /// cost-side position.
  List<LedgerRow> _toRows(List<JournalEntry> entries) {
    double running = 0;
    return entries.map((e) {
      running += e.debit - e.credit;
      final memo = (e.description?.isNotEmpty ?? false)
          ? e.description!
          : Accounts.byId(e.accountId).name;
      return LedgerRow(
        date: e.createdAt,
        memo: memo,
        debit: e.debit,
        credit: e.credit,
        balance: running,
      );
    }).toList();
  }

  Future<void> _exportPdf(List<JournalEntry> entries) async {
    await PdfGenerator.previewProjectLedger(ProjectLedgerData(
      projectName: widget.project.name,
      rows: entries,
      generatedAt: DateTime.now(),
      period: formatPeriod(_from, _to),
    ));
  }

  Future<void> _exportCsv(List<JournalEntry> entries) async {
    final rows = _toRows(entries);
    final csv = CsvExport.build(
      headers: const [
        'Date',
        'Particulars',
        'Debit',
        'Credit',
        'Running'
      ],
      rows: [
        ['Period:', formatPeriod(_from, _to), '', '', ''],
        ['', '', '', '', ''],
        ...rows.map((r) => [
              fmtDate(r.date),
              r.memo,
              r.debit > 0 ? r.debit.toStringAsFixed(2) : '',
              r.credit > 0 ? r.credit.toStringAsFixed(2) : '',
              r.balance.toStringAsFixed(2),
            ]),
      ],
    );
    await CsvExport.share(
      fileName:
          'project_ledger_${widget.project.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Project Ledger — ${widget.project.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ledgerVersionProvider);
    final entriesAsync = ref.watch(_projectEntriesProvider(_FilterKey(
      projectId: widget.project.id,
      from: _from,
      to: _to,
    )));

    return Scaffold(
      appBar: AppBar(
        title: Text('Ledger · ${widget.project.name}'),
        actions: [
          LedgerExportActions(
            enabled: entriesAsync.hasValue &&
                (entriesAsync.value?.isNotEmpty ?? false),
            onExportPdf: () async {
              final e = await ref.read(_projectEntriesProvider(_FilterKey(
                projectId: widget.project.id,
                from: _from,
                to: _to,
              )).future);
              await _exportPdf(e);
            },
            onExportCsv: () async {
              final e = await ref.read(_projectEntriesProvider(_FilterKey(
                projectId: widget.project.id,
                from: _from,
                to: _to,
              )).future);
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
            title: widget.project.name,
            subtitle: '${widget.project.model.label}'
                '${widget.project.clientName != null ? ' · ${widget.project.clientName}' : ''}'
                ' · Period: ${formatPeriod(_from, _to)}',
            rows: rows,
            totalLabel: 'Net Cost-Side Position',
            totalValue: total,
            signedTotal: true,
            emptyMessage: 'No transactions for this project in the period.',
            headerBelowTitle: DateRangeBar(
              from: _from,
              to: _to,
              onChanged: (f, t) => setState(() {
                _from = f;
                _to = t;
              }),
            ),
          );
        },
      ),
    );
  }
}

/// Composite cache key so each (project, from, to) triple is its own
/// FutureProvider instance — refreshing one window doesn't invalidate
/// every other open project ledger.
class _FilterKey {
  final String projectId;
  final DateTime? from;
  final DateTime? to;
  const _FilterKey({required this.projectId, this.from, this.to});

  @override
  bool operator ==(Object other) =>
      other is _FilterKey &&
      other.projectId == projectId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(projectId, from, to);
}

final _projectEntriesProvider =
    FutureProvider.family<List<JournalEntry>, _FilterKey>((ref, key) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.entriesForProject(key.projectId, from: key.from, to: key.to);
});
