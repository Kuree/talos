// CLAUSE: Conditional expression selects one value
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
bit select=0;int n;
initial begin n=select?3:7;if(n!=7)$fatal(1,"result"); $display("PASS");end
endmodule
