// CLAUSE: Parameterized module header and named ports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child #(parameter N=3)(input bit[N-1:0]a,output wire[N-1:0]y);assign y=a;endmodule
module top;wire[3:0]y;child #(.N(4)) u(.a(4'h9),.y(y));
initial begin #1;if(y!==4'h9)$fatal;$display("PASS");end endmodule
