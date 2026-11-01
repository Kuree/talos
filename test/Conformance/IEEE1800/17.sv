// CLAUSE: Checkers
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: CHECKER_MATCH

checker C(input event e);
 a:assert property(@e 1'b1) $display("CHECKER_MATCH"); else $fatal;
endchecker
module top; bit clk=0; C inst(posedge clk);
 initial begin #1; clk=1; #1; $display("PASS"); $finish; end
endmodule
