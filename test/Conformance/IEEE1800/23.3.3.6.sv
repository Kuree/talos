// CLAUSE: uwire port
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(output wire y);assign y=1;endmodule
module top;uwire y;cell_t d(y);initial begin #1;if(y!==1)$fatal;$display("PASS");$finish;end endmodule
