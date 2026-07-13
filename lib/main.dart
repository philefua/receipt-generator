import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/business_settings.dart';
import 'models/product_preset.dart';
import 'models/receipt.dart';
import 'pages/backend_page.dart';
import 'state/app_state_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(BusinessSettingsAdapter());
  Hive.registerAdapter(ProductPresetAdapter());
  Hive.registerAdapter(ReceiptItemAdapter());
  Hive.registerAdapter(ReceiptAdapter());

  final controller = AppStateController();
  await controller.init();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const ReceiptGeneratorApp(),
    ),
  );
}

class ReceiptGeneratorApp extends StatelessWidget {
  const ReceiptGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        cardTheme: const CardThemeData(
          elevation: 1,
          margin: EdgeInsets.all(8),
        ),
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    CashierPage(),
    BackendPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Cashier',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: 'Manager',
          ),
        ],
      ),
    );
  }
}

class CashierPage extends StatefulWidget {
  const CashierPage({super.key});

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage> {
  final TextEditingController _cashierNameController =
      TextEditingController(text: 'Cashier');
  final TextEditingController _discountController =
      TextEditingController(text: '0');

  @override
  void dispose() {
    _cashierNameController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _checkout(BuildContext context) async {
    final controller = context.read<AppStateController>();
    if (controller.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty.')),
      );
      return;
    }
    try {
      final receipt = await controller.finalizeAndSaveReceipt(
        cashierName: _cashierNameController.text.trim().isEmpty
            ? 'Cashier'
            : _cashierNameController.text.trim(),
      );
      if (!context.mounted) return;
      _discountController.text = '0';
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sale Completed'),
          content: Text(
            'Receipt Code: ${receipt.receiptCode}\n'
            'Total Paid: ${controller.settings.currencySymbol}'
            '${receipt.totalPayable.toStringAsFixed(2)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e')),
      );
    }
  }

  Widget _buildProductGrid(BuildContext context, double width) {
    final controller = context.watch<AppStateController>();
    final products = controller.productPresets;
    final crossAxisCount = width >= 1000
        ? 5
        : width >= 700
            ? 4
            : width >= 480
                ? 3
                : 2;

    if (products.isEmpty) {
      return const Center(
        child: Text('No active products. Add some from the Manager tab.'),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: products.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return Card(
          child: InkWell(
            onTap: () => controller.addToCart(product),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${controller.settings.currencySymbol}${product.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartPanel(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final currency = controller.settings.currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _cashierNameController,
            decoration: const InputDecoration(
              labelText: 'Cashier Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: controller.cart.isEmpty
              ? const Center(child: Text('Cart is empty'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: controller.cart.length,
                  itemBuilder: (context, index) {
                    final item = controller.cart[index];
                    return Card(
                      child: ListTile(
                        title: Text(item.product.name),
                        subtitle: Text(
                          '$currency${item.product.price.toStringAsFixed(2)} each',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => controller.updateCartQuantity(
                                item.product.id,
                                item.quantity - 1,
                              ),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => controller.updateCartQuantity(
                                item.product.id,
                                item.quantity + 1,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  controller.removeFromCart(item.product.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _discountController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Discount %',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null && parsed >= 0 && parsed <= 100) {
                controller.setDiscountPercent(parsed);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _totalsRow('Subtotal', controller.subtotal, currency),
              _totalsRow('Discount', -controller.discountAmount, currency),
              const Divider(),
              _totalsRow(
                'Total Payable',
                controller.totalPayable,
                currency,
                bold: true,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: controller.cart.isEmpty
                      ? null
                      : () => controller.clearCart(),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _checkout(context),
                  child: const Text('Complete Sale'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _totalsRow(String label, double value, String currency,
      {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('$currency${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          if (isWide) {
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildProductGrid(context, constraints.maxWidth),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 340,
                  child: _buildCartPanel(context),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(
                flex: 3,
                child: _buildProductGrid(context, constraints.maxWidth),
              ),
              const Divider(height: 1),
              Expanded(
                flex: 4,
                child: _buildCartPanel(context),
              ),
            ],
          );
        },
      ),
    );
  }
}