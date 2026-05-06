import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'transaction_form_screen.dart';

class TransactionPickerScreen extends StatelessWidget {
  const TransactionPickerScreen({super.key});

  /// Service Fee was removed from the picker — for Labour-Rate projects the
  /// fee is configured on the project itself (`Project.serviceFeePercent`)
  /// and posted automatically when the project is closed/reconciled, so a
  /// manual fee transaction is no longer a meaningful thing for the user
  /// to add.
  ///
  /// Personal / Owner Draw is back in the picker — it's the canonical way
  /// to record cash leaving the construction system from any cash-like
  /// account (Cash, Wallet, Bank). Use it whenever money leaves a wallet
  /// or bank for non-construction purposes.
  static const _visibleKinds = <TxnKind>[
    TxnKind.materialBuy,
    TxnKind.labourPayment,
    TxnKind.labourCredit,
    TxnKind.supplierPay,
    TxnKind.receiveFromProject,
    TxnKind.walletTransfer,
    TxnKind.personalDraw,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Transaction')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _visibleKinds.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final kind = _visibleKinds[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_iconFor(kind))),
              title: Text(kind.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(kind.blurb),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionFormScreen(kind: kind),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(TxnKind k) => switch (k) {
        TxnKind.materialBuy => Icons.inventory_2,
        TxnKind.labourPayment => Icons.engineering,
        TxnKind.labourCredit => Icons.handyman,
        TxnKind.supplierPay => Icons.payments,
        TxnKind.receiveFromProject => Icons.account_balance_wallet,
        TxnKind.walletTransfer => Icons.swap_horiz,
        TxnKind.personalDraw => Icons.shopping_bag,
        TxnKind.serviceFee => Icons.percent,
      };
}
