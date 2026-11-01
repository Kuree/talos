// CLAUSE: dissimilar net collapse
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(output wor y);assign y=0;endmodule
module top;wire y;assign y=1;cell_t d(y);initial begin #1;if(y!==1)$fatal;$display("PASS");$finish;end endmodule
