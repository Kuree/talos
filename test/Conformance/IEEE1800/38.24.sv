// CLAUSE: vpi_mcd_close closes vpi_mcd_open and $fopen channels, returning 0, and returns the mcd of channels it could not close
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/38.24/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.24.vpi.out
// RUN: %FileCheck %s --check-prefix=FILE1 --input-file=38.24.sv.out
// CHECK: close=0 name=null
// CHECK-NEXT: closed again=1
// CHECK-NEXT: channel 1 kept=1
// CHECK-NEXT: $fopen close=0 name=null
// CHECK-NEXT: mixed close=1 closed valid=1
// CHECK-NEXT: $fopen fd close=0 name=null
// CHECK-NEXT: still printing
// FILE0: written before the close
// FILE1: written from source

module top;
import "DPI-C" context function void probe(input int mcd, fd);
int mcd, fd;
initial begin
  mcd = $fopen("38.24.sv.out");
  fd = $fopen("38.24.fd.out", "w");
  $fdisplay(mcd, "written from source");
  probe(mcd, fd);
  $display("still printing");
  $finish;
end
endmodule
