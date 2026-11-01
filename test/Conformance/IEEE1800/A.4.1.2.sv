// CLAUSE: Interface instance with ordered parameters
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface I #(parameter N=7);endinterface
module top;
I #(3)i();
initial begin if(i.N!=3)$fatal(1,"result"); $display("PASS");end
endmodule
