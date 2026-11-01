// CLAUSE: ANSI UDP port declarations
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

primitive identity(output q,input a);table 0:0;1:1;endtable endprimitive
module top;
wire q;identity u(q,1'b1);
initial begin #1;if(q!==1)$fatal(1,"result"); $display("PASS");end
endmodule
