// RUN: talos -emit-talos %s | FileCheck %s
// RUN: talos --emit-dpi-header %s | FileCheck %s --check-prefix=HEADER

module dpi_deprecated_export;
  function int legacy_export(input bit [7:0] value);
    return value;
  endfunction
  export "DPI" function legacy_export;
endmodule

// CHECK: dpi_export_c_identifier = "legacy_export"
// CHECK-SAME: dpi_legacy
// HEADER: int32_t legacy_export(const svBitPackedArrRef arg0);
