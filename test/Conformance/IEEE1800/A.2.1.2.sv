// CLAUSE: Typed input and output port declarations
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child(input logic a,output logic y);always_comb y=~a;endmodule
module top;
wire y;child u(1'b0,y);
initial begin #1;if(y!==1)$fatal(1,"result"); $display("PASS");end
endmodule
