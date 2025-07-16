import 'package:flutter_test/flutter_test.dart';
import 'package:silver_printer/silver_printer.dart';
import 'package:silver_printer/silver_printer_platform_interface.dart';
import 'package:silver_printer/silver_printer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSilverPrinterPlatform
    with MockPlatformInterfaceMixin
    implements SilverPrinterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SilverPrinterPlatform initialPlatform = SilverPrinterPlatform.instance;

  test('$MethodChannelSilverPrinter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSilverPrinter>());
  });

  test('getPlatformVersion', () async {
    SilverPrinter silverPrinterPlugin = SilverPrinter();
    MockSilverPrinterPlatform fakePlatform = MockSilverPrinterPlatform();
    SilverPrinterPlatform.instance = fakePlatform;

    expect(await silverPrinterPlugin.getPlatformVersion(), '42');
  });
}
