// CLAUSE: sequential level latch
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

primitive p(output reg q,input en,d); initial q=0; table 1 0:?:0; 1 1:?:1; 0 ?:?:-; endtable endprimitive
module top;
timeunit 1ns; timeprecision 1ns;
logic en=0,d=0; wire q; p u(q,en,d);
initial begin
#1; if(q!==0) $fatal; d=1; #1; if(q!==0) $fatal; en=1; #1; if(q!==1) $fatal; en=0; #1; d=0; #1; if(q!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
