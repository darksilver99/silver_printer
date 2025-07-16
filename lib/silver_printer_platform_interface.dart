import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'silver_printer_method_channel.dart';

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
}
