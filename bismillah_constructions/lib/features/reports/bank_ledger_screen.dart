import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/models/bank.dart';
import '../../data/models/journal_entry.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../common/ledger_view.dart';
import 'csv_export.dart';
import 'pdf_generator.dart';

/// Lists user-defined banks/wallets so the user can drill into a specific
/// account's ledger.
class BankLedgerPickerScreen extends ConsumerWidget {
  const BankLedgerPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banks = ref.watch(banksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Bank / Wallet')),
      body: AsyncView<List<Bank>>(
        value: banks,
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No banks or wallets yet. Add one from Settings → Banks & Wallets.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final b = list[i];
              return Card(
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.account_balance)),
                  title: Text(b.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      b.accountNo == null ? null : Text('Acct ${b.accountNo}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BankLedgerScreen(bank: b),
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

/// Per-bank ledger: every journal entry that touched this bank/wallet, with a
/// running balance (debits − credits = positive cash). Exports to PDF and CSV.
class BankLedgerScreen extends ConsumerWidget {
  const BankLedgerScreen({super.key, required this.bank});
  final Bank bank;

  /// Convert raw journal entries into LedgerRows with a running balance
  /// (debits = inflows for an asset account).
  List<LedgerRow> _toRows(List<JournalEntry> entries) {
    double running = 0;
    return entries.map((r) {
      running += r.debit - r.credit;
      return LedgerRow(
        date: r.createdAt,
        memo: r.description ?? '—',
        debit: r.debit,
        credit: r.credit,
        balance: running,
      );
    }).toList();
  }

  Future<void> _exportPdf(WidgetRef ref) async {
    final entries = await ref.read(_bankEntriesProvider(bank.id).future);
    await PdfGenerator.previewBankLedger(BankLedgerData(
      bankName: bank.name,
      rows: entries,
      generatedAt: DateTime.now(),
    ));
  }

  Future<void> _exportCsv(WidgetRef ref) async {
    final entries = await ref.read(_bankEntriesProvider(bank.id).future);
    final rows = _toRows(entries);
    final csv = CsvExport.build(
      headers: ['Date', 'Memo', 'Debit (in)', 'Credit (out)', 'Balance'],
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
          'bank_ledger_${bank.name}_${DateTime.now().millisecondsSinceEpoch}',
      csv: csv,
      subject: 'Bank Ledger — ${bank.name}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerVersionProvider);
    final entriesAsync = ref.watch(_bankEntriesProvider(bank.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Ledger · ${bank.name}'),
        actions: [
          LedgerExportActions(
            enabled: entriesAsync.hasValue &&
                (entriesAsync.value?.isNotEmpty ?? false),
            onExportPdf: () => _exportPdf(ref),
            onExportCsv: () => _exportCsv(ref),
          ),
        ],
      ),
      body: AsyncView<List<JournalEntry>>(
        value: entriesAsync,
        data: (entries) {
          final rows = _toRows(entries);
          final total = rows.isEmpty ? 0.0 : rows.last.balance;
          return LedgerView(
            title: bank.name,
            subtitle: bank.accountNo == null ? '' : 'Acct ${bank.accountNo}',
            rows: rows,
            totalLabel: 'Net Balance',
            totalValue: total,
            signedTotal: true,
            debitHeader: 'Dr (in)',
            creditHeader: 'Cr (out)',
            emptyMessage: 'No transactions for this account yet.',
          );
        },
      ),
    );
  }
}

final _bankEntriesProvider =
    FutureProvider.family<List<JournalEntry>, String>((ref, bankId) async {
  ref.watch(ledgerVersionProvider);
  final repo = await ref.watch(ledgerRepoProvider.future);
  return repo.entriesForAccount(bankId);
});
