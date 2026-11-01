// CLAUSE: input net coercion
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a);assign a=1;endmodule
module top;wire a;cell_t d(a);initial begin #1;if(a!==1)$fatal;$display("PASS");$finish;end endmodule
