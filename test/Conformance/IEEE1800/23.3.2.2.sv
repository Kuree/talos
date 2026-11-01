// CLAUSE: ansi ports
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input logic a,output logic y);always_comb y=a;endmodule
module top;logic y;cell_t d(.a(1'b1),.y(y));initial begin #1;if(y!==1)$fatal;$display("PASS");$finish;end endmodule
