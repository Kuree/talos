// CLAUSE: cycle literal default
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;

initial begin

#(1:2:3); if($time!=2) $fatal(1,"t=%0t",$time);

$display("PASS"); $finish;
end
endmodule
