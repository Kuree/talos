// CLAUSE: Width-check command and notifier update
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child(input wire c);reg n=0;
specify $width(posedge c,2,0,n);endspecify endmodule
module top;bit c=0;child u(c);
initial begin #1;c=1;#1;c=0;#1;if(u.n!==1)$fatal;$display("PASS");end endmodule
