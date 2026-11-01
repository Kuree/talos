// CLAUSE: disable unsampled
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; bit clk,reset; int actions;
always @(posedge clk) reset<=1;
ap: assert property (@(posedge clk) disable iff(reset) 0) actions++; else actions++;
initial begin #1; clk=1; #1; if(actions!=0) $fatal(1,"actions=%0d",actions); $display("PASS"); $finish; end
endmodule
