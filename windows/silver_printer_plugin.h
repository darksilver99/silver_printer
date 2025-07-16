#ifndef FLUTTER_PLUGIN_SILVER_PRINTER_PLUGIN_H_
#define FLUTTER_PLUGIN_SILVER_PRINTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace silver_printer {

class SilverPrinterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SilverPrinterPlugin();

  virtual ~SilverPrinterPlugin();

  // Disallow copy and assign.
  SilverPrinterPlugin(const SilverPrinterPlugin&) = delete;
  SilverPrinterPlugin& operator=(const SilverPrinterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace silver_printer

#endif  // FLUTTER_PLUGIN_SILVER_PRINTER_PLUGIN_H_
