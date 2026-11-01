// CLAUSE: Hierarchy
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(a,y);input a;output y;wire a,y;assign y=a;endmodule
module top;wire y;cell_t d(1'b1,y);initial begin #1;if(y!==1)$fatal;$display("PASS");$finish;end endmodule
