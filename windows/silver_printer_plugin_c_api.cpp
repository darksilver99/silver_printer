#include "include/silver_printer/silver_printer_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "silver_printer_plugin.h"

void SilverPrinterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  silver_printer::SilverPrinterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
