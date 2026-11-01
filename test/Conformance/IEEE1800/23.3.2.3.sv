// CLAUSE: implicit named ports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a,output wire y);assign y=a;endmodule
module top;wire a=1,y;cell_t d(.a,.y);initial begin #1;if(y!==1)$fatal;$display("PASS");$finish;end endmodule
