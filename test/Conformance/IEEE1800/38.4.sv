// CLAUSE: vpi_control: vpiStop and vpiFinish run $stop and $finish on return, vpiReset restarts from time 0, vpiSetInteractiveScope succeeds
// XFAIL: *
// vpi_control works, but $reset (D.8) runs the executable again, so the helper's static call count starts over and every run resets once more until the harness times the RUN out.
// RUN: %clang -c -fPIC %S/Inputs/38.4/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %t.exe +stop
// CHECK: start t=0 x=0
// CHECK-NEXT: scope=1
// CHECK-NEXT: reset=1
// CHECK-NEXT: start t=0 x=0
// CHECK-NEXT: finish=1
// CHECK-NOT: not reached
// CHECK: start t=0 x=0
// CHECK-NEXT: stop=1
// CHECK-NOT: not reached

module top;
int x = 0;
import "DPI-C" context function void probe(input int stop);
initial begin
  $display("start t=%0t x=%0d", $time, x);
  x = 1;
  #5 probe($test$plusargs("stop"));
  $display("not reached");
end
endmodule
