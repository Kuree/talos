// CLAUSE: virtual modport clocking
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface I(input logic clk);logic data=1;clocking cb@(posedge clk);input data;endclocking modport M(clocking cb);endinterface
module top;logic clk;I i(clk);virtual I.M v;
initial begin v=i;#1;clk=1;#1;if(v.cb.data!==1)$fatal;$display("PASS");$finish;end endmodule
