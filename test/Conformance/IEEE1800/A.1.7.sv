// CLAUSE: Program declaration with an initial item
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

program P;int n;initial begin n=7;if(n!=7)$fatal;$display("PASS");end endprogram
module top;P p();endmodule
