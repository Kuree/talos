// CLAUSE: wait dynamic size
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;

int data[]; bit done=0;
initial wait(data.size()==2) done=1;
initial begin #1; data=new[2]; #1; if(!done) $fatal; $display("PASS"); $finish; end

endmodule
