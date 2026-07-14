import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/receipt.dart';
import '../services/thermal_printer_service.dart';
import '../state/app_state_controller.dart';
import '../widgets/receipt_preview_widget.dart';

/// Read-only list of every finalized receipt, newest first, with a
/// tap-to-view detail screen and a reprint action on each entry.
class ReceiptHistoryPage extends StatelessWidget {
  const ReceiptHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final receipts = controller.receiptHistory;
    final currency = controller.settings.currencySymbol;
    final dateFormat = DateFormat('yyyy-MM-dd  HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt History'),
      ),
      body: receipts.isEmpty
          ? const Center(
              child: Text('No receipts have been generated yet.'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: receipts.length,
              itemBuilder: (context, index) {
                final receipt = receipts[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      receipt.receiptCode,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${receipt.customerName.isNotEmpty ? receipt.customerName : 'Walk-in customer'}\n'
                      '${dateFormat.format(receipt.issuedAt)} • ${receipt.paymentMethod}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      '$currency${receipt.totalPayable.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailPage(receipt: receipt),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// Full detail view of a single past receipt, with a reprint button.
class ReceiptDetailPage extends StatefulWidget {
  final Receipt receipt;

  const ReceiptDetailPage({super.key, required this.receipt});

  @override
  State<ReceiptDetailPage> createState() => _ReceiptDetailPageState();
}

class _ReceiptDetailPageState extends State<ReceiptDetailPage> {
  bool _isPrinting = false;

  Future<void> _handlePrint(AppStateController controller) async {
    setState(() => _isPrinting = true);
    final result = await ThermalPrinterService.instance.printReceipt(
      receipt: widget.receipt,
      business: controller.settings,
    );
    if (!mounted) return;
    setState(() => _isPrinting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Receipt ${widget.receipt.receiptCode}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ReceiptPreviewWidget(
            receipt: widget.receipt,
            business: controller.settings,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isPrinting ? null : () => _handlePrint(controller),
        icon: _isPrinting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.print_outlined),
        label: Text(_isPrinting ? 'Printing...' : 'Reprint Receipt'),
      ),
    );
  }
}