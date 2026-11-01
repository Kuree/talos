// CLAUSE: negative check condition
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire c,d,output reg n=0);timeunit 1ns;timeprecision 1ps;specify $setuphold(posedge c,posedge d,-2,5,n,,1'b0); endspecify endmodule
// 31.9.2 gives $setuphold(clk, data, s, h, ntfr, , cond1) as equivalent to a
// $setup and $hold pair, with each event conditioned by the role it has there.
module cell_pair(input wire c,d,ts,tc,output reg n1=0,n2=0);timeunit 1ns;timeprecision 1ns;
specify
  $setuphold(posedge c,d,3,3,n1,ts,tc);
  $setup(d&&&ts,posedge c&&&tc,3,n2);
  $hold(posedge c&&&ts,d&&&tc,3,n2);
endspecify
endmodule
module top;timeunit 1ns;timeprecision 1ps;logic c=0,d=0;wire n;cell_t dut(c,d,n);
logic pc=0,pd=0,ts=0,tc=0;wire n1,n2;int c1=0,c2=0;cell_pair pair(pc,pd,ts,tc,n1,n2);
always @(n1) c1++;
always @(n2) c2++;
initial begin #10;c=1;#3;d=1;#4;if(n!==0)$fatal;
for(int i=0;i<16;i++)begin
  ts=i[0];tc=i[1];#10 pd=~pd;#1 pc=1;#1 pd=~pd;#10 pc=0;
  ts=i[2];tc=i[3];#1 pd=~pd;#2 pc=1;#2 pc=0;
end
#10;if(c1!=c2||c2==0)$fatal(1,"single %0d, pair %0d",c1,c2);
$display("PASS");$finish;end endmodule
