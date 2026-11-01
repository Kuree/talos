// CLAUSE: Attribute instance attached to a declaration
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
(* keep=1 *) bit n=1;
initial begin if(n!==1)$fatal(1,"result"); $display("PASS");end
endmodule
