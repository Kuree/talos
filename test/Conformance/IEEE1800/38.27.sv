// CLAUSE: vpi_mcd_open gives each file its own channel bit, returns the same descriptor for an open file, including one from $fopen, and 0 on error
// XFAIL: *
// The runtime has no vpi_mcd_open, vpi_mcd_printf or vpi_mcd_close (undefined symbols at link).
// RUN: %clang -c -fPIC %S/Inputs/38.27/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.27.a.out
// RUN: %FileCheck %s --check-prefix=FILE1 --input-file=38.27.b.out
// CHECK: single bits=1 distinct=1 reserved=0
// CHECK-NEXT: reopen same=1 $fopen same=1
// CHECK-NEXT: bad path=0
// FILE0: to a
// FILE0-NEXT: to both
// FILE1: to b
// FILE1-NEXT: to both

module top;
import "DPI-C" context function void probe(input int mcd);
initial begin probe($fopen("38.27.sv.out")); $finish; end
endmodule
