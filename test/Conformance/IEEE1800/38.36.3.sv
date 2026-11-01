// CLAUSE: Action callbacks: cbEndOfCompile, cbStartOfSimulation and cbEndOfSimulation fire in order, on $finish or an empty queue, and cbPLIError on a failed VPI call
// XFAIL: *
// The three lifecycle callbacks work, but vpi_register_cb rejects the other required actions such as cbPLIError (docs/vpi.md: other callback reasons are not implemented).
// RUN: %clang -shared -fPIC %S/Inputs/38.36.3/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// RUN: %t.exe +drain
// CHECK: cbEndOfCompile user=compile
// CHECK-NEXT: cbPLIError registered=1
// CHECK-NEXT: cbStartOfSimulation user=start
// CHECK-NEXT: running t=0
// CHECK-NEXT: cbPLIError user=error level=1
// CHECK-NEXT: last statement t=2
// CHECK-NEXT: cbEndOfSimulation user=end
// CHECK: cbEndOfCompile user=compile
// CHECK: last statement t=2
// CHECK-NEXT: cbEndOfSimulation user=end

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" context function void fail();
initial begin
  $display("running t=%0t", $time);
  #1 fail();
  #1 $display("last statement t=%0t", $time);
  if (!$test$plusargs("drain")) $finish;
end
endmodule
