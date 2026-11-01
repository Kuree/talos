// RUN: talos -emit-talos %s | FileCheck %s

module dpi_deprecated_import;
  import "DPI" function int legacy_import(input logic [7:0] value);
endmodule

// CHECK: dpi_c_identifier = "legacy_import"
// CHECK-SAME: is_dpi_import
