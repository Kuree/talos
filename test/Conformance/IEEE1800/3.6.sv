// CLAUSE: checker execution
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

checker check_true(event clock_event, logic value);
  a: assert property (@clock_event value) else $fatal(1,"checker failed");
endchecker
module top;
  bit clk=0;
  always #5 clk=~clk;
  check_true c(posedge clk,1'b1);
  initial begin #11; $display("PASS"); $finish; end
endmodule
