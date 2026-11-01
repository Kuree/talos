// CLAUSE: Neutral satisfaction propagates assertion local variables
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;bit clk;int a=3,n;
property p;int v;@(posedge clk)(1,v=a)|->(v==3);endproperty
assert property(p)n++;else $fatal(1,"local state satisfaction");
initial begin #1;clk=1;#1;if(n!=1)$fatal(1,"assertion attempt");$display("PASS");$finish;end endmodule
