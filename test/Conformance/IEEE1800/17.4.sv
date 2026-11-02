// CLAUSE: checker context clock
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: CHECK

checker c(input bit value,input event e=$inferred_clock);
a:assert property(@e value)$display("CHECK");else $fatal;endchecker
module top;bit clk,value=1;always @(posedge clk)c inst(value);
initial begin #1;clk=1;#1;$display("PASS");$finish;end endmodule
