import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'silver_printer_platform_interface.dart';

/// An implementation of [SilverPrinterPlatform] that uses method channels.
class MethodChannelSilverPrinter extends SilverPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('silver_printer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
