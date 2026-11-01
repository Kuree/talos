// CLAUSE: Explicit edge list and timing-check condition
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child(input wire c,en);reg n=0;
specify $width(edge [01] c &&& en,2,0,n);endspecify endmodule
module top;bit c=0;child u(c,1'b1);
initial begin #1;c=1;#1;c=0;#1;if(u.n!==1)$fatal;$display("PASS");end endmodule
