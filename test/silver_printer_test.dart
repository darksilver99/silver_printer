import 'package:flutter_test/flutter_test.dart';
import 'package:silver_printer/silver_printer.dart';
import 'package:silver_printer/silver_printer_platform_interface.dart';
import 'package:silver_printer/silver_printer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:typed_data';

class MockSilverPrinterPlatform
    with MockPlatformInterfaceMixin
    implements SilverPrinterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> isBluetoothAvailable() => Future.value(true);

  @override
  Future<bool> requestBluetoothPermissions() => Future.value(true);

  @override
  Future<void> startScan() => Future.value();

  @override
  Future<void> stopScan() => Future.value();

  @override
  Future<List<BluetoothDevice>> getDiscoveredDevices() => Future.value([]);

  @override
  Future<List<BluetoothDevice>> getPairedDevices() => Future.value([]);

  @override
  Future<bool> connect(String deviceId) => Future.value(true);

  @override
  Future<bool> disconnect() => Future.value(true);

  @override
  Future<ConnectionState> getConnectionState() =>
      Future.value(ConnectionState.disconnected);

  @override
  Future<BluetoothDevice?> getConnectedDevice() => Future.value(null);

  @override
  Future<bool> isConnected() => Future.value(false);

  @override
  Future<PrinterStatus> getPrinterStatus() =>
      Future.value(PrinterStatus.offline);

  @override
  Future<bool> printText(String text, {Map<String, dynamic>? settings}) =>
      Future.value(true);

  @override
  Future<bool> printImage(
    Uint8List imageData, {
    int? width,
    int? height,
    Map<String, dynamic>? settings,
  }) => Future.value(true);

  @override
  Future<bool> printJob(PrintJob job) => Future.value(true);

  @override
  Future<bool> feedPaper(int lines) => Future.value(true);

  @override
  Future<bool> cutPaper() => Future.value(true);

  @override
  Future<bool> sendRawData(Uint8List data) => Future.value(true);

  @override
  Future<bool> printHybrid(
    List<PrintItem> items, {
    Map<String, dynamic>? settings,
  }) => Future.value(true);

  @override
  Stream<BluetoothDevice> get deviceDiscoveryStream => Stream.empty();

  @override
  Stream<ConnectionState> get connectionStateStream => Stream.empty();

  @override
  Stream<PrinterStatus> get printerStatusStream => Stream.empty();
}

void main() {
  final SilverPrinterPlatform initialPlatform = SilverPrinterPlatform.instance;

  test('$MethodChannelSilverPrinter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSilverPrinter>());
  });

  test('getPlatformVersion', () async {
    SilverPrinter silverPrinterPlugin = SilverPrinter.instance;
    MockSilverPrinterPlatform fakePlatform = MockSilverPrinterPlatform();
    SilverPrinterPlatform.instance = fakePlatform;

    expect(await silverPrinterPlugin.getPlatformVersion(), '42');
  });
}
