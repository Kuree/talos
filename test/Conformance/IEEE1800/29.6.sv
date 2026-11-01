// CLAUSE: sequential potential edges
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

primitive p(output reg q,input clk,d); initial q=0; table p 0:?:0; p 1:?:1; n ?:?:-; ? *:?:-; endtable endprimitive
module top;
timeunit 1ns; timeprecision 1ns;
logic clk=0,d=1; wire q; p u(q,clk,d);
initial begin
#1; clk=1'bx; #1; if(q!==1) $fatal; clk=1; #1; if(q!==1) $fatal; clk=0; d=0; #1; clk=1; #1; if(q!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
