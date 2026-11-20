// RUN: talos -emit-talos %s | FileCheck %s
// RUN: talos --emit-dpi-header %s -o %t.h 2>&1 | FileCheck %s --check-prefix=WARN
// RUN: FileCheck %s --check-prefix=HEADER < %t.h

module dpi_deprecated_import;
  import "DPI" function int legacy_import(input logic [7:0] value);
endmodule

// CHECK: dpi_c_identifier = "legacy_import"
// CHECK-SAME: dpi_legacy
// CHECK-SAME: is_dpi_import
// WARN: 'DPI' is deprecated and should be replaced with 'DPI-C'
// WARN-SAME: may require changes to the application's C code
// HEADER: int32_t legacy_import(const svLogicPackedArrRef arg0);
