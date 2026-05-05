import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/journal_entry.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  bool _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    final entries = _showDeleted
        ? ref.watch(allEntriesIncludingDeletedProvider)
        : ref.watch(allEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Transactions'),
        actions: [
          Row(
            children: [
              const Text('Show deleted',
                  style: TextStyle(fontSize: 13)),
              Switch(
                value: _showDeleted,
                onChanged: (v) => setState(() => _showDeleted = v),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: AsyncView<List<JournalEntry>>(
        value: entries,
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('No transactions yet.'));
          }
          final pairs = <String, List<JournalEntry>>{};
          for (final r in rows) {
            (pairs[r.transactionId] ??= []).add(r);
          }
          final txnIds = pairs.keys.toList();

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: txnIds.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final pair = pairs[txnIds[i]]!;
              if (pair.length != 2) return const SizedBox.shrink();
              final dr = pair.firstWhere((e) => e.debit > 0);
              final cr = pair.firstWhere((e) => e.credit > 0);
              final isDeleted = dr.deleted;

              return Card(
                color: isDeleted
                    ? Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: 0.18)
                    : null,
                child: InkWell(
                  onLongPress: () =>
                      _showActions(context, ref, dr.transactionId, isDeleted),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              fmtMoney(dr.debit),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: isDeleted
                                          ? BalanceColors.negative(context)
                                          : null,
                                      decoration: isDeleted
                                          ? TextDecoration.lineThrough
                                          : null),
                            ),
                            Row(
                              children: [
                                if (isDeleted)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Text('DELETED',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                if (dr.synced == 0 && !isDeleted)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(Icons.sync,
                                        size: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary),
                                  ),
                                Text(fmtDateTime(dr.createdAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Dr  ${Accounts.byId(dr.accountId).name}',
                            style: TextStyle(
                              decoration: isDeleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            )),
                        Text('     Cr  ${Accounts.byId(cr.accountId).name}',
                            style: TextStyle(
                              decoration: isDeleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            )),
                        if (dr.description != null &&
                            dr.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(dr.description!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                        const SizedBox(height: 4),
                        Text('Long-press for actions',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
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

  void _showActions(BuildContext context, WidgetRef ref, String txnId,
      bool isDeleted) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            if (!isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Soft Delete'),
                subtitle: const Text(
                    'Removed from active balance, kept in archive with strikethrough'),
                onTap: () async {
                  final ledger = await ref.read(ledgerRepoProvider.future);
                  await ledger.softDeleteTransaction(txnId);
                  bumpLedger(ref);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            if (isDeleted)
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore'),
                onTap: () async {
                  final ledger = await ref.read(ledgerRepoProvider.future);
                  await ledger.restoreTransaction(txnId);
                  bumpLedger(ref);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            if (!isDeleted)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Post Reversing Entry'),
                subtitle: const Text(
                    'Adds an offsetting transaction (recommended for accounting integrity)'),
                onTap: () async {
                  final ledger = await ref.read(ledgerRepoProvider.future);
                  await ledger.postReversal(txnId);
                  bumpLedger(ref);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
