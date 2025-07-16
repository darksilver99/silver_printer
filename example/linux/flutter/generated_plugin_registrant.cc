//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <silver_printer/silver_printer_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) silver_printer_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SilverPrinterPlugin");
  silver_printer_plugin_register_with_registrar(silver_printer_registrar);
}
