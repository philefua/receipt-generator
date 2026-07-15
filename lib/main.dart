import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/business_settings.dart';
import 'models/product_preset.dart';
import 'models/receipt.dart';
import 'pages/backend_page.dart';
import 'pages/frontend_page.dart';
import 'pages/printer_setup_page.dart';
import 'pages/receipt_history_page.dart';
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
    FrontendPage(),
    BackendPage(),
  ];

  static const List<String> _titles = [
    'Cashier',
    'Manager',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Printer Setup',
            icon: const Icon(Icons.print_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrinterSetupPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Receipt History',
            icon: const Icon(Icons.history_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReceiptHistoryPage(),
                ),
              );
            },
          ),
        ],
      ),
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