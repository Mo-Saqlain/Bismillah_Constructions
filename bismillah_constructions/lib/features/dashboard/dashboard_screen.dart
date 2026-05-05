import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/bank.dart';
import '../../data/sync/sync_service.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_history_screen.dart';
import '../transactions/transaction_picker_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(accountSummaryProvider);
    final banks = ref.watch(banksProvider);
    final recent = ref.watch(recentEntriesProvider);
    final sync = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        title: const Text('Bismillah'),
        actions: [
          _SyncIndicator(status: sync),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const TransactionPickerScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Transaction'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          bumpLedger(ref);
          await ref.read(syncServiceFutureProvider.future).then(
                (s) => s.syncNow(),
              );
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            AsyncView(
              value: summary,
              data: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TreasuryCard(
                    liquidCash: s.liquidCash,
                    netLiquidity: s.netLiquidity,
                    netPosition: s.netPosition,
                    netWorth: s.totalNetWorth,
                  ),
                  const SizedBox(height: 8),
                  AsyncView<List<Bank>>(
                    value: banks,
                    data: (banksList) => _BalanceCard(
                      title: 'Liquid Cash',
                      value: s.liquidCash,
                      icon: Icons.account_balance,
                      breakdown: [
                        ('Cash', s.cash),
                        ('Supervisor Float', s.supervisorFloat),
                        for (final b in banksList)
                          (b.name, s.bankBalances[b.id] ?? 0),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                            label: 'Payables',
                            value: s.payables,
                            positive: false),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                            label: 'Net Liquidity',
                            value: s.netLiquidity,
                            positive: s.netLiquidity >= 0),
                      ),
                    ],
                  ),
                  if (s.counterReceivables > 0 || s.counterPayables > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _StatTile(
                                label: 'Counter Recv',
                                value: s.counterReceivables,
                                positive: true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _StatTile(
                                label: 'Counter Pay',
                                value: s.counterPayables,
                                positive: false)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  _PnlCard(
                      revenue: s.revenue,
                      serviceFee: s.serviceFeeIncome,
                      material: s.materialCosts,
                      labour: s.labourCosts,
                      personalDraw: s.personalDraw,
                      net: s.netProfit),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Activity',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TransactionHistoryScreen()),
                  ),
                  child: const Text('See all'),
                ),
              ],
            ),
            AsyncView(
              value: recent,
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No transactions yet — tap + to start.')),
                  );
                }
                final seen = <String>{};
                final debitRows = rows
                    .where((e) => e.debit > 0 && seen.add(e.transactionId))
                    .take(8)
                    .toList();
                return Column(
                  children: debitRows.map((e) {
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(fmtMoney(e.debit)),
                        subtitle: Text(
                          e.description ?? fmtDateTime(e.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: e.synced == 0
                            ? const Icon(Icons.sync, size: 16)
                            : Icon(Icons.cloud_done,
                                size: 16,
                                color: BalanceColors.positive(context)),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TreasuryCard extends StatelessWidget {
  const _TreasuryCard({
    required this.liquidCash,
    required this.netLiquidity,
    required this.netPosition,
    required this.netWorth,
  });
  final double liquidCash;
  final double netLiquidity;
  final double netPosition;
  final double netWorth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Treasury Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 12),
            Row(
              children: [
                _TreasuryCell(
                    label: 'Liquid Cash',
                    value: liquidCash,
                    onContainer: true),
                const SizedBox(width: 8),
                _TreasuryCell(
                    label: 'Net Liquidity',
                    value: netLiquidity,
                    onContainer: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _TreasuryCell(
                    label: 'Net Position',
                    value: netPosition,
                    onContainer: true),
                const SizedBox(width: 8),
                _TreasuryCell(
                    label: 'Net Worth',
                    value: netWorth,
                    onContainer: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Net Liquidity = Liquid Cash − Supplier Payables (actual spendable).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreasuryCell extends StatelessWidget {
  const _TreasuryCell(
      {required this.label,
      required this.value,
      this.onContainer = false});
  final String label;
  final double value;
  final bool onContainer;

  @override
  Widget build(BuildContext context) {
    final color = BalanceColors.signed(context, value);
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: onContainer
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface)),
          const SizedBox(height: 2),
          Text(fmtSignedMoney(value),
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: color)),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.breakdown,
  });
  final String title;
  final double value;
  final IconData icon;
  final List<(String, double)> breakdown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(fmtMoney(value),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: BalanceColors.signed(context, value))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: breakdown
                  .where((b) => b.$2 != 0)
                  .map((b) => Text('${b.$1}: ${fmtMoney(b.$2)}',
                      style: Theme.of(context).textTheme.bodySmall))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.positive});
  final String label;
  final double value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive
        ? BalanceColors.positive(context)
        : BalanceColors.negative(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(fmtMoney(value),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _PnlCard extends StatelessWidget {
  const _PnlCard({
    required this.revenue,
    required this.serviceFee,
    required this.material,
    required this.labour,
    required this.personalDraw,
    required this.net,
  });
  final double revenue;
  final double serviceFee;
  final double material;
  final double labour;
  final double personalDraw;
  final double net;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profit & Loss (all-time)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _row(context, 'Project Revenue', revenue),
            if (serviceFee != 0)
              _row(context, 'Service Fee Income', serviceFee),
            _row(context, 'Material Costs', -material),
            _row(context, 'Labour Costs', -labour),
            if (personalDraw != 0)
              _row(context, 'Personal / Daily Draw', -personalDraw),
            const Divider(),
            _row(context, 'Net', net,
                bold: true, color: BalanceColors.signed(context, net)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, double v,
      {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      color: color ?? (v < 0 ? BalanceColors.negative(context) : null),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.status});
  final AsyncValue<SyncStatus> status;

  @override
  Widget build(BuildContext context) {
    return status.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const Icon(Icons.cloud_off),
      data: (s) {
        final (icon, label) = switch (s.state) {
          SyncState.idle => (Icons.cloud_done, 'Synced'),
          SyncState.syncing => (Icons.cloud_sync, 'Syncing…'),
          SyncState.error => (Icons.cloud_off, 'Sync error'),
          SyncState.offline => (Icons.cloud_off, 'Offline'),
          SyncState.disabled => (Icons.cloud_outlined, 'Local'),
        };
        return Tooltip(
          message: '$label${s.pending > 0 ? ' · ${s.pending} pending' : ''}',
          child: Icon(icon),
        );
      },
    );
  }
}
