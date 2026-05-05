import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'transaction_form_screen.dart';

class TransactionPickerScreen extends StatelessWidget {
  const TransactionPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Transaction')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: TxnKind.values.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final kind = TxnKind.values[i];
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
        TxnKind.supplierPay => Icons.payments,
        TxnKind.receiveFromProject => Icons.account_balance_wallet,
        TxnKind.walletTransfer => Icons.swap_horiz,
        TxnKind.personalDraw => Icons.shopping_bag,
        TxnKind.serviceFee => Icons.percent,
      };
}
