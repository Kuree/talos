// CLAUSE: vpi_register_assertion_cb reports each attempt's start, success and failure on that assertion, with times and user data, until removed
// XFAIL: *
// The runtime has no vpi_register_assertion_cb (undefined symbol at link).
// RUN: %clang -c -fPIC %S/Inputs/39.4.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: registered=3
// CHECK-NEXT: start time=5 attempt=5 name=a1 user=tag
// CHECK-NEXT: success time=5 attempt=5 name=a1 user=tag
// CHECK-NEXT: start time=15 attempt=15 name=a1 user=tag
// CHECK-NEXT: failure time=15 attempt=15 name=a1 user=tag fail_expr=1
// CHECK-NEXT: removed=1
// CHECK-NEXT: done t=25

module top;
timeunit 1ns; timeprecision 1ns;
logic clk = 0, ok = 1;
a1: assert property (@(posedge clk) ok) else $display("a1 fail action t=%0t", $time);
a2: assert property (@(posedge clk) !ok) else ; // no callbacks: they are per assertion
import "DPI-C" context function void setup();
import "DPI-C" context function void drop();
initial begin
  setup();
  #5 clk = 1;
  #5 clk = 0; ok = 0;
  #5 clk = 1;
  #5 clk = 0; drop();
  #5 clk = 1; // no callbacks after the removal
  $display("done t=%0t", $time);
  $finish;
end
endmodule
