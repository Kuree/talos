// CLAUSE: assertoff control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; bit clk; int actions, control;
ap: assert property (@(posedge clk) 0) actions++; else actions++;
initial begin $assertoff; #1; clk=1; #1; if(actions!=0) $fatal;
$asserton; clk=0; #1; clk=1; #1; if(actions!=1) $fatal;
control=4; $assertcontrol(control); clk=0; #1; clk=1; #1; if(actions!=1) $fatal;
control=3; $assertcontrol(control); clk=0; #1; clk=1; #1; if(actions!=2) $fatal;
$display("PASS"); $finish; end endmodule
