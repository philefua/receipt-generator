import 'package:flutter/material.dart';

import '../balance_repository.dart';
import '../screens/balance_payment_page.dart';

/// The cashier's entry point for balance payments. It sits on the cashier
/// screen but opens its own page, so the normal sale flow is never touched.
/// Hidden when finance data is unavailable on this device.
class BalancePaymentButton extends StatelessWidget {
  const BalancePaymentButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!BalanceRepository.instance.isReady) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          try {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BalancePaymentPage()),
            );
          } catch (_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open Balance Payment.')),
            );
          }
        },
        icon: const Icon(Icons.account_balance_wallet_outlined),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('Balance Payment (customer paying what they owe)'),
        ),
      ),
    );
  }
}
