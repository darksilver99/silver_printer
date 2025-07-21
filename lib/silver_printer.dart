import 'dart:typed_data';
import 'silver_printer_platform_interface.dart';
import 'print_item.dart';

export 'silver_printer_platform_interface.dart'
    show
        BluetoothDevice,
        BluetoothDeviceType,
        ConnectionState,
        PrinterStatus,
        PrintJob;
export 'print_item.dart';

class SilverPrinter {
  static SilverPrinter? _instance;

  SilverPrinter._();

  static SilverPrinter get instance {
    _instance ??= SilverPrinter._();
    return _instance!;
  }

  Future<String?> getPlatformVersion() {
    return SilverPrinterPlatform.instance.getPlatformVersion();
  }

  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() {
    return SilverPrinterPlatform.instance.isBluetoothAvailable();
  }

  /// Request Bluetooth permissions (required on Android)
  Future<bool> requestBluetoothPermissions() {
    return SilverPrinterPlatform.instance.requestBluetoothPermissions();
  }

  /// Start scanning for Bluetooth devices
  Future<void> startScan() {
    return SilverPrinterPlatform.instance.startScan();
  }

  /// Stop scanning for Bluetooth devices
  Future<void> stopScan() {
    return SilverPrinterPlatform.instance.stopScan();
  }

  /// Get list of discovered devices during scan
  Future<List<BluetoothDevice>> getDiscoveredDevices() {
    return SilverPrinterPlatform.instance.getDiscoveredDevices();
  }

  /// Get list of paired/bonded devices
  Future<List<BluetoothDevice>> getPairedDevices() {
    return SilverPrinterPlatform.instance.getPairedDevices();
  }

  /// Connect to a specific Bluetooth device
  Future<bool> connect(String deviceId) {
    return SilverPrinterPlatform.instance.connect(deviceId);
  }

  /// Disconnect from currently connected device
  Future<bool> disconnect() {
    return SilverPrinterPlatform.instance.disconnect();
  }

  /// Get current connection state
  Future<ConnectionState> getConnectionState() {
    return SilverPrinterPlatform.instance.getConnectionState();
  }

  /// Get currently connected device info
  Future<BluetoothDevice?> getConnectedDevice() {
    return SilverPrinterPlatform.instance.getConnectedDevice();
  }

  /// Check if currently connected to any device
  Future<bool> isConnected() {
    return SilverPrinterPlatform.instance.isConnected();
  }

  /// Get current printer status
  Future<PrinterStatus> getPrinterStatus() {
    return SilverPrinterPlatform.instance.getPrinterStatus();
  }

  /// Print text with optional formatting settings
  Future<bool> printText(String text, {Map<String, dynamic>? settings}) {
    return SilverPrinterPlatform.instance.printText(text, settings: settings);
  }

  /// Print image from byte data
  Future<bool> printImage(
    Uint8List imageData, {
    int? width,
    int? height,
    Map<String, dynamic>? settings,
  }) {
    return SilverPrinterPlatform.instance.printImage(
      imageData,
      width: width,
      height: height,
      settings: settings,
    );
  }

  /// Print a complete job with text and/or image
  Future<bool> printJob(PrintJob job) {
    return SilverPrinterPlatform.instance.printJob(job);
  }

  /// Feed paper by specified number of lines
  Future<bool> feedPaper(int lines) {
    return SilverPrinterPlatform.instance.feedPaper(lines);
  }

  /// Cut paper (if printer supports it)
  Future<bool> cutPaper() {
    return SilverPrinterPlatform.instance.cutPaper();
  }

  /// Send raw ESC/POS command data
  Future<bool> sendRawData(Uint8List data) {
    return SilverPrinterPlatform.instance.sendRawData(data);
  }

  /// Print hybrid content (mix of text and images) for better performance on iOS
  Future<bool> printHybrid(
    List<PrintItem> items, {
    Map<String, dynamic>? settings,
  }) {
    return SilverPrinterPlatform.instance.printHybrid(
      items,
      settings: settings,
    );
  }

  /// Stream of newly discovered devices during scanning
  Stream<BluetoothDevice> get deviceDiscoveryStream {
    return SilverPrinterPlatform.instance.deviceDiscoveryStream;
  }

  /// Stream of connection state changes
  Stream<ConnectionState> get connectionStateStream {
    return SilverPrinterPlatform.instance.connectionStateStream;
  }

  /// Stream of printer status changes
  Stream<PrinterStatus> get printerStatusStream {
    return SilverPrinterPlatform.instance.printerStatusStream;
  }
}
