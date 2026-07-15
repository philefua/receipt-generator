import 'package:flutter/material.dart';

import '../services/thermal_printer_service.dart';

/// Lets the cashier grant Bluetooth permissions, scan for paired printers,
/// and connect to one. Meant to be opened once per shift rather than per
/// transaction — the connection persists across the app until disconnected
/// or the app is closed.
class PrinterSetupPage extends StatefulWidget {
  const PrinterSetupPage({super.key});

  @override
  State<PrinterSetupPage> createState() => _PrinterSetupPageState();
}

class _PrinterSetupPageState extends State<PrinterSetupPage> {
  bool _isLoading = false;
  bool _isConnecting = false;
  String? _connectingAddress;
  List<PrinterDevice> _devices = [];
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final granted = await ThermalPrinterService.instance.requestPermissions();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage =
            'Bluetooth permission was denied. Enable it in device Settings to see paired printers.';
        _statusIsError = true;
      });
      return;
    }

 try {
      final devices = await ThermalPrinterService.instance.getPairedDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _isLoading = false;
        if (devices.isEmpty) {
          _statusMessage =
              'No paired printers found. Pair your thermal printer in device Bluetooth settings first, then tap Refresh.';
          _statusIsError = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Could not read paired printers: $e';
        _statusIsError = true;
      });
    }
  }

  Future<void> _connectTo(PrinterDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingAddress = device.address;
      _statusMessage = null;
    });

    final result = await ThermalPrinterService.instance.connect(
      device.address,
      name: device.name,
    );

    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _connectingAddress = null;
      _statusMessage = result.message;
      _statusIsError = !result.success;
    });
  }

  Future<void> _disconnect() async {
    setState(() => _isLoading = true);
    final result = await ThermalPrinterService.instance.disconnect();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _statusMessage = result.message;
      _statusIsError = !result.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ThermalPrinterService.instance.isConnected;
    final connectedAddress = ThermalPrinterService.instance.connectedAddress;
    final connectedName = ThermalPrinterService.instance.connectedName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Setup'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: isConnected
                  ? Colors.green.shade50
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: isConnected
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected ? 'Connected' : 'Not Connected',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (isConnected)
                            Text(
                              connectedName ?? connectedAddress ?? '',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                    ),
                    if (isConnected)
                      TextButton(
                        onPressed: _isLoading ? null : _disconnect,
                        child: const Text('Disconnect'),
                      ),
                  ],
                ),
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusIsError
                        ? Colors.red.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusIsError
                        ? Colors.red.shade800
                        : Colors.blue.shade800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Paired Printers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No paired printers found.'),
                ),
              )
            else
              ..._devices.map((device) {
                final isThisConnected =
                    isConnected && connectedAddress == device.address;
                final isThisConnecting =
                    _isConnecting && _connectingAddress == device.address;

                return Card(
                  child: ListTile(
                    leading: Icon(
                      isThisConnected
                          ? Icons.bluetooth_connected
                          : Icons.print_outlined,
                      color: isThisConnected ? Colors.green.shade700 : null,
                    ),
                    title: Text(device.name.isNotEmpty
                        ? device.name
                        : 'Unnamed device'),
                    subtitle: Text(device.address),
                    trailing: isThisConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : isThisConnected
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : ElevatedButton(
                                onPressed: _isConnecting
                                    ? null
                                    : () => _connectTo(device),
                                child: const Text('Connect'),
                              ),
                  ),
                );
              }),
            const SizedBox(height: 20),
            Card(
              color: Colors.grey.shade100,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Tip: If your printer is not listed, pair it first via '
                  'your device\'s Bluetooth settings (outside this app), '
                  'then return here and tap Refresh.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}