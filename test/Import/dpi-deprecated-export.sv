// RUN: talos -emit-talos %s | FileCheck %s

module dpi_deprecated_export;
  function int legacy_export(input int value);
    return value;
  endfunction
  export "DPI" function legacy_export;
endmodule

// CHECK: dpi_export_c_identifier = "legacy_export"
