// CLAUSE: A checker models an auxiliary variable and asserts on it; nets in a checker are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/17.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: member not allowed in checker declaration
// CHECK: 25 count=2{{$}}
// CHECK-NEXT: 35 count=3{{$}}

// 17.1: the assertion can only fail if the checker's own modeling code advances count.
checker running_count(logic d, event clk_i);
  bit [3:0] count = 0;
  always_ff @clk_i count <= count + d;
  assert property (@clk_i count < 2)
    else $display("%0t count=%0d", $time, $sampled(count));
endchecker
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk = 0, d = 1;
  always #5 clk = ~clk;
  running_count check(d, posedge clk);
  initial #36 $finish;
endmodule
