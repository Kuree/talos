// CLAUSE: interface ports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface I(input logic a);logic y;assign y=a;endinterface
module top;I i(1'b1);initial begin #1;if(i.y!==1)$fatal;$display("PASS");$finish;end endmodule
