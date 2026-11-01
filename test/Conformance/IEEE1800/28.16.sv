// CLAUSE: gate rise fall delay
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
logic a=0; wire y; buf #(2,3) g(y,a);
initial begin
#5; a=1; #1; if(y!==0) $fatal; #2; if(y!==1) $fatal; a=0; #2; if(y!==1) $fatal; #2; if(y!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
