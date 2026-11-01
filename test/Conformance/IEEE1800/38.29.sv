// CLAUSE: vpi_mcd_vprintf writes to an mcd from an already started va_list and returns the character count
// XFAIL: *
// The runtime has no vpi_mcd_open, vpi_mcd_vprintf or vpi_mcd_close (undefined symbols at link).
// RUN: %clang -c -fPIC %S/Inputs/38.29/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.29.out
// CHECK: count=10
// CHECK-NEXT: rest count=6
// FILE0: a=12 b=xy
// FILE0-NEXT: v=222

module top;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
