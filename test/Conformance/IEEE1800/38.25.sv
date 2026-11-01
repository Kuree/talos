// CLAUSE: vpi_mcd_flush returns 0 and makes vpi_mcd_printf text visible in the file before it is closed
// XFAIL: *
// The runtime has no vpi_mcd_open, vpi_mcd_printf, vpi_mcd_flush or vpi_mcd_close (undefined symbols at link).
// RUN: %clang -c -fPIC %S/Inputs/38.25/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.25.out
// CHECK: flush=0
// CHECK-NEXT: read while open: first line
// FILE0: first line
// FILE0-NEXT: second line

module top;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
