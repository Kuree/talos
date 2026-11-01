// CLAUSE: If statement with an else branch
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int n;
initial begin if(1)n=7;else n=3;if(n!=7)$fatal(1,"result"); $display("PASS");end
endmodule
