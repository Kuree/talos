// CLAUSE: time literal fine precision control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 10ns/1ps; realtime value=2.1ns;
initial begin
if(value<0.209 || value>0.211) $fatal;
$display("PASS"); $finish;
end
endmodule
