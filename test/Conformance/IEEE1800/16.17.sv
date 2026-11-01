// CLAUSE: expect boolean control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; bit clk; int actions;
initial begin expect(@(posedge clk) 1) actions++; else $fatal;
if($time!=1 || actions!=1) $fatal; $display("PASS"); $finish; end
initial begin #1; clk=1; #1; $fatal(1,"expect timeout"); end endmodule
