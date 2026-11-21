// CLAUSE: vpi_printf writes C-formatted text to standard output and the active log and returns the character count
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/38.30/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=LOG --input-file=38.30.log
// CHECK: before
// CHECK-NEXT: n=7 s=abc x=ff f= 1.50
// CHECK-NEXT: after count=23
// CHECK-NEXT: n=7 s=abc x=ff f= 1.50
// LOG: before
// LOG-NEXT: n=7 s=abc x=ff f= 1.50
// LOG-NEXT: after count=23
// LOG-NOT: n=7

module top;
import "DPI-C" context function int probe();
int count;
initial begin
  $log("38.30.log");
  $display("before");
  count = probe();
  $display("after count=%0d", count);
  $nolog;
  count = probe();
  $finish;
end
endmodule
