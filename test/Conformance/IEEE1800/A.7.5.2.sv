// CLAUSE: Setup-check limit and notifier arguments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child(input wire c,d);reg n=0;localparam L=2;
specify $setup(posedge d,posedge c,L,n);endspecify endmodule
module top;bit c=0,d=0;child u(c,d);
initial begin #1;d=1;#1;c=1;#1;if(u.n!==1)$fatal;$display("PASS");end endmodule
