
import 'silver_printer_platform_interface.dart';

class SilverPrinter {
  Future<String?> getPlatformVersion() {
    return SilverPrinterPlatform.instance.getPlatformVersion();
  }
}
