// CLAUSE: parameters
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module dut_unit#(parameter N=3)(output int v);localparam L=N+1;assign v=L;endmodule
module top;int v;dut_unit#(.N(5))d(v);initial begin #1;if(v!=6)$fatal(1,"parameter/localparam");$display("PASS");$finish;end endmodule
