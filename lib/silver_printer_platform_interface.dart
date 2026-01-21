import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:typed_data';

import 'silver_printer_method_channel.dart';
import 'print_item.dart';

enum BluetoothDeviceType { classic, ble, unknown }

enum ConnectionState { disconnected, connecting, connected, disconnecting }

enum PrinterStatus { ready, busy, error, offline }

class BluetoothDevice {
  final String id;
  final String name;
  final String address;
  final BluetoothDeviceType type;
  final int? rssi;
  final bool isPaired;

  const BluetoothDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.type,
    this.rssi,
    this.isPaired = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'type': type.name,
      'rssi': rssi,
      'isPaired': isPaired,
    };
  }

  static BluetoothDevice fromMap(Map<String, dynamic> map) {
    return BluetoothDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unknown Device',
      address: map['address'] ?? '',
      type: BluetoothDeviceType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => BluetoothDeviceType.unknown,
      ),
      rssi: map['rssi'],
      isPaired: map['isPaired'] ?? false,
    );
  }
}

class PrintJob {
  final String text;
  final Uint8List? imageData;
  final int? imageWidth;
  final int? imageHeight;
  final Map<String, dynamic> settings;

  const PrintJob({
    this.text = '',
    this.imageData,
    this.imageWidth,
    this.imageHeight,
    this.settings = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'imageData': imageData,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'settings': settings,
    };
  }
}

abstract class SilverPrinterPlatform extends PlatformInterface {
  /// Constructs a SilverPrinterPlatform.
  SilverPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static SilverPrinterPlatform _instance = MethodChannelSilverPrinter();

  /// The default instance of [SilverPrinterPlatform] to use.
  ///
  /// Defaults to [MethodChannelSilverPrinter].
  static SilverPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SilverPrinterPlatform] when
  /// they register themselves.
  static set instance(SilverPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() {
    throw UnimplementedError(
      'isBluetoothAvailable() has not been implemented.',
    );
  }

  /// Request Bluetooth permissions (Android)
  Future<bool> requestBluetoothPermissions() {
    throw UnimplementedError(
      'requestBluetoothPermissions() has not been implemented.',
    );
  }

  /// Start scanning for Bluetooth devices
  Future<void> startScan() {
    throw UnimplementedError('startScan() has not been implemented.');
  }

  /// Stop scanning for Bluetooth devices
  Future<void> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  /// Get list of discovered devices
  Future<List<BluetoothDevice>> getDiscoveredDevices() {
    throw UnimplementedError(
      'getDiscoveredDevices() has not been implemented.',
    );
  }

  /// Get list of paired/bonded devices
  Future<List<BluetoothDevice>> getPairedDevices() {
    throw UnimplementedError('getPairedDevices() has not been implemented.');
  }

  /// Connect to a Bluetooth device
  Future<bool> connect(String deviceId) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnect from current device
  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Clear connection cache (forget preferred protocols)
  Future<bool> clearConnectionCache() {
    throw UnimplementedError('clearConnectionCache() has not been implemented.');
  }

  /// Get current connection state
  Future<ConnectionState> getConnectionState() {
    throw UnimplementedError('getConnectionState() has not been implemented.');
  }

  /// Get currently connected device
  Future<BluetoothDevice?> getConnectedDevice() {
    throw UnimplementedError('getConnectedDevice() has not been implemented.');
  }

  /// Check if currently connected to a device
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }

  /// Get printer status
  Future<PrinterStatus> getPrinterStatus() {
    throw UnimplementedError('getPrinterStatus() has not been implemented.');
  }

  /// Print text
  Future<bool> printText(String text, {Map<String, dynamic>? settings}) {
    throw UnimplementedError('printText() has not been implemented.');
  }

  /// Print image from bytes
  Future<bool> printImage(
    Uint8List imageData, {
    int? width,
    int? height,
    Map<String, dynamic>? settings,
  }) {
    throw UnimplementedError('printImage() has not been implemented.');
  }

  /// Print combined text and image
  Future<bool> printJob(PrintJob job) {
    throw UnimplementedError('printJob() has not been implemented.');
  }

  /// Feed paper
  Future<bool> feedPaper(int lines) {
    throw UnimplementedError('feedPaper() has not been implemented.');
  }

  /// Cut paper (if supported)
  Future<bool> cutPaper() {
    throw UnimplementedError('cutPaper() has not been implemented.');
  }

  /// Send raw ESC/POS commands
  Future<bool> sendRawData(Uint8List data) {
    throw UnimplementedError('sendRawData() has not been implemented.');
  }

  /// Print hybrid content (mix of text and images)
  Future<bool> printHybrid(
    List<PrintItem> items, {
    Map<String, dynamic>? settings,
  }) {
    throw UnimplementedError('printHybrid() has not been implemented.');
  }

  /// Get device discovery stream
  Stream<BluetoothDevice> get deviceDiscoveryStream {
    throw UnimplementedError('deviceDiscoveryStream has not been implemented.');
  }

  /// Get connection state stream
  Stream<ConnectionState> get connectionStateStream {
    throw UnimplementedError('connectionStateStream has not been implemented.');
  }

  /// Get printer status stream
  Stream<PrinterStatus> get printerStatusStream {
    throw UnimplementedError('printerStatusStream has not been implemented.');
  }
}
