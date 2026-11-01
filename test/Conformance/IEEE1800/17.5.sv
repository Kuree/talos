// CLAUSE: checker ff assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: OLD

checker c(input event clock);bit v=0;
always_ff @clock begin assert(!v)$display("OLD");else $fatal;v<=1;end
endchecker
module top;bit clk;c inst(posedge clk);
initial begin #1;clk=1;#1;$display("PASS");$finish;end endmodule
