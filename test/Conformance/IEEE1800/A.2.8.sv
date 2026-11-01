// CLAUSE: Automatic declaration in a named block
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;initial begin:scope automatic int n=7;if(n!=7)$fatal;$display("PASS");end endmodule
