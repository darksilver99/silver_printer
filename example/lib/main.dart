import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:silver_printer/silver_printer.dart' as printer;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Silver Printer Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _printer = printer.SilverPrinter.instance;
  bool _bluetoothAvailable = false;
  printer.ConnectionState _connectionState = printer.ConnectionState.disconnected;
  printer.BluetoothDevice? _connectedDevice;
  
  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
    _listenToConnectionState();
  }

  Future<void> _initializeBluetooth() async {
    final available = await _printer.isBluetoothAvailable();
    setState(() {
      _bluetoothAvailable = available;
    });
    
    if (!available) {
      await _printer.requestBluetoothPermissions();
    }
  }

  void _listenToConnectionState() {
    _printer.connectionStateStream.listen((state) {
      setState(() {
        _connectionState = state;
      });
      if (state == printer.ConnectionState.connected) {
        _updateConnectedDevice();
      } else {
        setState(() {
          _connectedDevice = null;
        });
      }
    });
  }

  Future<void> _updateConnectedDevice() async {
    final device = await _printer.getConnectedDevice();
    setState(() {
      _connectedDevice = device;
    });
  }

  Future<void> _checkConnectionAndNavigate() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    // Check both connection state and printer status
    final isConnected = await _printer.isConnected();
    
    // Try to ping the printer to verify actual connection
    bool actuallyConnected = false;
    if (isConnected) {
      try {
        // Try to get printer status as a connectivity test
        final status = await _printer.getPrinterStatus();
        actuallyConnected = (status != printer.PrinterStatus.offline);
      } catch (e) {
        // Connection test failed - printer is not actually connected
        actuallyConnected = false;
      }
    }
    
    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog
    
    if (actuallyConnected) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PrintPreviewScreen()),
      );
    } else {
      // If not actually connected, disconnect and go to device list
      if (isConnected) {
        await _printer.disconnect();
      }
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DeviceListScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Silver Printer Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bluetooth Status',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _bluetoothAvailable ? Icons.bluetooth : Icons.bluetooth_disabled,
                            color: _bluetoothAvailable ? Colors.blue : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(_bluetoothAvailable ? 'Available' : 'Unavailable'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connection Status',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _getConnectionIcon(),
                            color: _getConnectionColor(),
                          ),
                          const SizedBox(width: 8),
                          Text(_getConnectionText()),
                        ],
                      ),
                      if (_connectedDevice != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Connected to: ${_connectedDevice!.name}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          'Type: ${_connectedDevice!.type.name.toUpperCase()}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _printer.disconnect();
                          },
                          icon: const Icon(Icons.link_off, size: 16),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Food Order Receipt',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Order #12345', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('1x Pad Thai - ฿150'),
                      Text('2x Green Curry - ฿240'),
                      Text('1x Mango Sticky Rice - ฿80'),
                      Divider(),
                      Text('Total: ฿470', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _bluetoothAvailable ? _checkConnectionAndNavigate : null,
                icon: const Icon(Icons.print),
                label: const Text('Print Receipt'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getConnectionIcon() {
    switch (_connectionState) {
      case printer.ConnectionState.connected:
        return Icons.link;
      case printer.ConnectionState.connecting:
        return Icons.sync;
      case printer.ConnectionState.disconnecting:
        return Icons.link_off;
      case printer.ConnectionState.disconnected:
        return Icons.link_off;
    }
  }

  Color _getConnectionColor() {
    switch (_connectionState) {
      case printer.ConnectionState.connected:
        return Colors.green;
      case printer.ConnectionState.connecting:
        return Colors.orange;
      case printer.ConnectionState.disconnecting:
        return Colors.orange;
      case printer.ConnectionState.disconnected:
        return Colors.red;
    }
  }

  String _getConnectionText() {
    switch (_connectionState) {
      case printer.ConnectionState.connected:
        return 'Connected';
      case printer.ConnectionState.connecting:
        return 'Connecting...';
      case printer.ConnectionState.disconnecting:
        return 'Disconnecting...';
      case printer.ConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final _printer = printer.SilverPrinter.instance;
  final List<printer.BluetoothDevice> _discoveredDevices = [];
  List<printer.BluetoothDevice> _sortedDevices = [];
  bool _isScanning = false;
  StreamSubscription<printer.BluetoothDevice>? _deviceSubscription;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _startListeningToDevices();
    _startScan();
  }

  @override
  void dispose() {
    _deviceSubscription?.cancel();
    _scanTimer?.cancel();
    _printer.stopScan();
    super.dispose();
  }

  void _startListeningToDevices() {
    _deviceSubscription = _printer.deviceDiscoveryStream.listen((device) {
      if (_isScanning) {
        setState(() {
          final index = _discoveredDevices.indexWhere((d) => d.id == device.id);
          if (index >= 0) {
            _discoveredDevices[index] = device;
          } else {
            _discoveredDevices.add(device);
          }
        });
      }
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
      _sortedDevices.clear();
    });
    
    try {
      await _printer.startScan();
      
      // Auto-stop scan after 10 seconds and sort the final list
      _scanTimer = Timer(const Duration(seconds: 10), () {
        _stopScanAndSort();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start scan: $e')),
        );
      }
    }
  }

  Future<void> _stopScanAndSort() async {
    await _printer.stopScan();
    
    // Sort devices by signal strength (strongest first) once and keep it stable
    final sortedDevices = List<printer.BluetoothDevice>.from(_discoveredDevices);
    sortedDevices.sort((a, b) {
      final aRssi = a.rssi ?? -100;
      final bRssi = b.rssi ?? -100;
      return bRssi.compareTo(aRssi); // Descending order (strongest first)
    });
    
    setState(() {
      _isScanning = false;
      _sortedDevices = sortedDevices;
    });
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    await _stopScanAndSort();
  }

  Future<void> _connectToDevice(printer.BluetoothDevice device) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final success = await _printer.connect(device.id);
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      
      if (success) {
        Navigator.pop(context); // Go back to main screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${device.name}')),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to connect')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Printer'),
        actions: [
          IconButton(
            onPressed: _isScanning ? _stopScan : _startScan,
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning) ...[
            const LinearProgressIndicator(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Scanning for devices...',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Available Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: (_isScanning ? _discoveredDevices : _sortedDevices).isEmpty
                ? Center(
                    child: Text(
                      _isScanning 
                        ? 'Searching for devices...' 
                        : 'No devices found.\nTap refresh to scan again.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _isScanning ? _discoveredDevices.length : _sortedDevices.length,
                    itemBuilder: (context, index) {
                      final device = _isScanning ? _discoveredDevices[index] : _sortedDevices[index];
                      return _buildDeviceListItem(device, false);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceListItem(printer.BluetoothDevice device, bool isPaired) {
    // Better device name with fallback
    String displayName = device.name;
    if (displayName == 'Unknown Device' || displayName.isEmpty) {
      if (device.address.isNotEmpty) {
        displayName = 'Device ${device.address.substring(device.address.length - 5)}';
      } else {
        displayName = 'Unknown Device';
      }
    }

    // Signal strength indicator
    String signalStrength = '';
    Color signalColor = Colors.grey;
    if (device.rssi != null) {
      if (device.rssi! > -50) {
        signalStrength = 'Excellent';
        signalColor = Colors.green;
      } else if (device.rssi! > -70) {
        signalStrength = 'Good';
        signalColor = Colors.orange;
      } else {
        signalStrength = 'Weak';
        signalColor = Colors.red;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          device.type == printer.BluetoothDeviceType.ble 
              ? Icons.bluetooth 
              : Icons.bluetooth_connected,
          color: Colors.blue,
          size: 32,
        ),
        title: Text(
          displayName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: device.type == printer.BluetoothDeviceType.ble 
                        ? Colors.purple.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    device.type.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: device.type == printer.BluetoothDeviceType.ble 
                          ? Colors.purple 
                          : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              device.address,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
            if (device.rssi != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.signal_cellular_alt,
                    size: 14,
                    color: signalColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$signalStrength (${device.rssi} dBm)',
                    style: TextStyle(
                      fontSize: 12,
                      color: signalColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: () => _connectToDevice(device),
      ),
    );
  }
}

class PrintPreviewScreen extends StatefulWidget {
  const PrintPreviewScreen({super.key});

  @override
  State<PrintPreviewScreen> createState() => _PrintPreviewScreenState();
}

class _PrintPreviewScreenState extends State<PrintPreviewScreen> {
  final _printer = printer.SilverPrinter.instance;
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  printer.PrinterStatus _printerStatus = printer.PrinterStatus.offline;
  StreamSubscription<printer.PrinterStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _listenToPrinterStatus();
    _updatePrinterStatus();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _listenToPrinterStatus() {
    _statusSubscription = _printer.printerStatusStream.listen((status) {
      setState(() {
        _printerStatus = status;
      });
    });
  }

  Future<void> _updatePrinterStatus() async {
    final status = await _printer.getPrinterStatus();
    setState(() {
      _printerStatus = status;
    });
  }

  Future<void> _printReceipt() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Printing...'),
            ],
          ),
        ),
      );

      // Capture the widget as image
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final imageBytes = byteData?.buffer.asUint8List();

        if (imageBytes != null) {
          final success = await _printer.printImage(
            imageBytes,
            width: 384,
            height: (384 * image.height / image.width).round(),
            settings: {
              'density': 'medium',
              'alignment': 'center',
            },
          );

          if (!mounted) return;
          Navigator.pop(context); // Close loading dialog

          if (success) {
            // Add some paper feed and cut
            await _printer.feedPaper(3);
            await _printer.cutPaper();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt printed successfully!')),
              );
              Navigator.pop(context); // Go back to main screen
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to print receipt')),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print Preview'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.grey[100],
            child: Row(
              children: [
                Icon(
                  _getPrinterStatusIcon(),
                  color: _getPrinterStatusColor(),
                ),
                const SizedBox(width: 8),
                Text('Printer: ${_getPrinterStatusText()}'),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _repaintBoundaryKey,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const ReceiptWidget(),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _printerStatus == printer.PrinterStatus.ready ? _printReceipt : null,
                icon: const Icon(Icons.print),
                label: const Text('Print Receipt'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPrinterStatusIcon() {
    switch (_printerStatus) {
      case printer.PrinterStatus.ready:
        return Icons.check_circle;
      case printer.PrinterStatus.busy:
        return Icons.hourglass_empty;
      case printer.PrinterStatus.error:
        return Icons.error;
      case printer.PrinterStatus.offline:
        return Icons.offline_bolt;
    }
  }

  Color _getPrinterStatusColor() {
    switch (_printerStatus) {
      case printer.PrinterStatus.ready:
        return Colors.green;
      case printer.PrinterStatus.busy:
        return Colors.orange;
      case printer.PrinterStatus.error:
        return Colors.red;
      case printer.PrinterStatus.offline:
        return Colors.grey;
    }
  }

  String _getPrinterStatusText() {
    switch (_printerStatus) {
      case printer.PrinterStatus.ready:
        return 'Ready';
      case printer.PrinterStatus.busy:
        return 'Printing...';
      case printer.PrinterStatus.error:
        return 'Error';
      case printer.PrinterStatus.offline:
        return 'Offline';
    }
  }
}

class ReceiptWidget extends StatelessWidget {
  const ReceiptWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Center(
          child: Text(
            'THAI KITCHEN',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Center(
          child: Text(
            '123 Food Street, Bangkok',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const Center(
          child: Text(
            'Tel: 02-123-4567',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Order #12345'),
            Text('2024-01-15 14:30'),
          ],
        ),
        const Divider(),
        const SizedBox(height: 8),
        _buildReceiptItem('1x Pad Thai', '฿150.00'),
        _buildReceiptItem('2x Green Curry', '฿240.00'),
        _buildReceiptItem('1x Mango Sticky Rice', '฿80.00'),
        const SizedBox(height: 8),
        const Divider(),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtotal:'),
            Text('฿470.00'),
          ],
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('VAT (7%):'),
            Text('฿32.90'),
          ],
        ),
        const Divider(),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TOTAL:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '฿502.90',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Thank you for your order!',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const Center(
          child: Text(
            'Please come again',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptItem(String name, String price) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(name)),
        Text(price),
      ],
    );
  }
}