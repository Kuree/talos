// CLAUSE: A formal interface port names its modport
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface bus;int a=3,b;modport view(input a,output b);endinterface
module leaf(bus.view p);initial p.b=p.a+1;endmodule
module top;bus b();leaf d(b);initial begin #1;if(b.b!=4)$fatal(1,"modport connection");$display("PASS");$finish;end endmodule
