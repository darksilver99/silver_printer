import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'silver_printer_platform_interface.dart';
import 'print_item.dart';

/// An implementation of [SilverPrinterPlatform] that uses method channels.
class MethodChannelSilverPrinter extends SilverPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('silver_printer');

  /// Event channel for device discovery
  static const EventChannel _deviceDiscoveryChannel = EventChannel('silver_printer/device_discovery');
  
  /// Event channel for connection state
  static const EventChannel _connectionStateChannel = EventChannel('silver_printer/connection_state');
  
  /// Event channel for printer status
  static const EventChannel _printerStatusChannel = EventChannel('silver_printer/printer_status');

  Stream<BluetoothDevice>? _deviceDiscoveryStream;
  Stream<ConnectionState>? _connectionStateStream;
  Stream<PrinterStatus>? _printerStatusStream;

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    final result = await methodChannel.invokeMethod<bool>('isBluetoothAvailable');
    return result ?? false;
  }

  @override
  Future<bool> requestBluetoothPermissions() async {
    final result = await methodChannel.invokeMethod<bool>('requestBluetoothPermissions');
    return result ?? false;
  }

  @override
  Future<void> startScan() async {
    await methodChannel.invokeMethod('startScan');
  }

  @override
  Future<void> stopScan() async {
    await methodChannel.invokeMethod('stopScan');
  }

  @override
  Future<List<BluetoothDevice>> getDiscoveredDevices() async {
    final result = await methodChannel.invokeMethod<List>('getDiscoveredDevices');
    if (result == null) return [];
    
    return result.map((deviceMap) => BluetoothDevice.fromMap(Map<String, dynamic>.from(deviceMap))).toList();
  }

  @override
  Future<List<BluetoothDevice>> getPairedDevices() async {
    final result = await methodChannel.invokeMethod<List>('getPairedDevices');
    if (result == null) return [];
    
    return result.map((deviceMap) => BluetoothDevice.fromMap(Map<String, dynamic>.from(deviceMap))).toList();
  }

  @override
  Future<bool> connect(String deviceId) async {
    final result = await methodChannel.invokeMethod<bool>('connect', {'deviceId': deviceId});
    return result ?? false;
  }

  @override
  Future<bool> disconnect() async {
    final result = await methodChannel.invokeMethod<bool>('disconnect');
    return result ?? false;
  }

  @override
  Future<ConnectionState> getConnectionState() async {
    final result = await methodChannel.invokeMethod<String>('getConnectionState');
    switch (result) {
      case 'connected':
        return ConnectionState.connected;
      case 'connecting':
        return ConnectionState.connecting;
      case 'disconnecting':
        return ConnectionState.disconnecting;
      default:
        return ConnectionState.disconnected;
    }
  }

  @override
  Future<BluetoothDevice?> getConnectedDevice() async {
    final result = await methodChannel.invokeMethod<Map>('getConnectedDevice');
    if (result == null) return null;
    
    return BluetoothDevice.fromMap(Map<String, dynamic>.from(result));
  }

  @override
  Future<bool> isConnected() async {
    final result = await methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }

  @override
  Future<PrinterStatus> getPrinterStatus() async {
    final result = await methodChannel.invokeMethod<String>('getPrinterStatus');
    switch (result) {
      case 'ready':
        return PrinterStatus.ready;
      case 'busy':
        return PrinterStatus.busy;
      case 'error':
        return PrinterStatus.error;
      default:
        return PrinterStatus.offline;
    }
  }

  @override
  Future<bool> printText(String text, {Map<String, dynamic>? settings}) async {
    final result = await methodChannel.invokeMethod<bool>('printText', {
      'text': text,
      'settings': settings ?? {},
    });
    return result ?? false;
  }

  @override
  Future<bool> printImage(Uint8List imageData, {int? width, int? height, Map<String, dynamic>? settings}) async {
    final result = await methodChannel.invokeMethod<bool>('printImage', {
      'imageData': imageData,
      'width': width,
      'height': height,
      'settings': settings ?? {},
    });
    return result ?? false;
  }

  @override
  Future<bool> printJob(PrintJob job) async {
    final result = await methodChannel.invokeMethod<bool>('printJob', job.toMap());
    return result ?? false;
  }

  @override
  Future<bool> feedPaper(int lines) async {
    final result = await methodChannel.invokeMethod<bool>('feedPaper', {'lines': lines});
    return result ?? false;
  }

  @override
  Future<bool> cutPaper() async {
    final result = await methodChannel.invokeMethod<bool>('cutPaper');
    return result ?? false;
  }

  @override
  Future<bool> sendRawData(Uint8List data) async {
    final result = await methodChannel.invokeMethod<bool>('sendRawData', {'data': data});
    return result ?? false;
  }

  @override
  Future<bool> printHybrid(List<PrintItem> items, {Map<String, dynamic>? settings}) async {
    final serializedItems = items.map((item) => item.toMap()).toList();
    final result = await methodChannel.invokeMethod<bool>('printHybrid', {
      'items': serializedItems,
      'settings': settings ?? {},
    });
    return result ?? false;
  }

  @override
  Stream<BluetoothDevice> get deviceDiscoveryStream {
    _deviceDiscoveryStream ??= _deviceDiscoveryChannel
        .receiveBroadcastStream()
        .map((event) => BluetoothDevice.fromMap(Map<String, dynamic>.from(event)));
    return _deviceDiscoveryStream!;
  }

  @override
  Stream<ConnectionState> get connectionStateStream {
    _connectionStateStream ??= _connectionStateChannel
        .receiveBroadcastStream()
        .map((event) {
          switch (event.toString()) {
            case 'connected':
              return ConnectionState.connected;
            case 'connecting':
              return ConnectionState.connecting;
            case 'disconnecting':
              return ConnectionState.disconnecting;
            default:
              return ConnectionState.disconnected;
          }
        });
    return _connectionStateStream!;
  }

  @override
  Stream<PrinterStatus> get printerStatusStream {
    _printerStatusStream ??= _printerStatusChannel
        .receiveBroadcastStream()
        .map((event) {
          switch (event.toString()) {
            case 'ready':
              return PrinterStatus.ready;
            case 'busy':
              return PrinterStatus.busy;
            case 'error':
              return PrinterStatus.error;
            default:
              return PrinterStatus.offline;
          }
        });
    return _printerStatusStream!;
  }
}
