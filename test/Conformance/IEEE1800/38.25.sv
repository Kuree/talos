// CLAUSE: vpi_mcd_flush returns 0 and makes vpi_mcd_printf text visible in the file before it is closed
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/38.25/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.25.out
// RUN: %FileCheck %s --check-prefix=LOG --implicit-check-not='stdout while paused' --input-file=38.25.log
// CHECK: flush=0
// CHECK-NEXT: read while open: first line
// CHECK-NEXT: log while open: first line
// CHECK-NEXT: buffered before pause
// CHECK-NEXT: stdout while paused
// CHECK-NEXT: paused flush=0
// CHECK-NEXT: paused log while open: buffered before pause
// FILE0: first line
// FILE0-NEXT: second line
// LOG: first line
// LOG-NEXT: buffered before pause

module top;
import "DPI-C" context function void probe();
import "DPI-C" context function void flush_paused();
initial begin
  $log("38.25.log");
  probe();
  $nolog;
  flush_paused();
end
endmodule
