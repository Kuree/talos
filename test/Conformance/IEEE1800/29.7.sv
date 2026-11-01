// CLAUSE: udp output initializer
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

primitive p(output reg q=1,input a); table b:?:-; endtable endprimitive
module top;
timeunit 1ns; timeprecision 1ns;
logic a=0; wire q; p u(q,a);
initial begin
#1; if(q!==1) $fatal; a=1; #1; if(q!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
