// CLAUSE: vpi_compatibility.h retargets the VPI routines in 2017 mode, and they read the design
// XFAIL: *
// vpi_compatibility.h, as printed in Annex L, has an empty #if for 2017 mode and a wrapped one-symbol guard, and the runtime has no vpi_*_<mode> routines.
// RUN: %clang -c -fPIC %S/Inputs/L.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=1 value=7 next=1
// Annex L maps each routine to its mode-specific name, here vpi_handle to vpi_handle_1800v2012, so these calls must link and work.

module top;
  int n = 7;
  import "DPI-C" context function void probe();
  initial begin
    probe();
    $finish;
  end
endmodule
