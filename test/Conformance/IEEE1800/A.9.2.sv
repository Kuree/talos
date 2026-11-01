// CLAUSE: Block and line comments separate tokens
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int n=1 /* middle */ +2; // tail
initial begin if(n!=3)$fatal(1,"result"); $display("PASS");end
endmodule
