// CLAUSE: block label hierarchy matching
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;

initial labeled: begin
  int local_value;
  local_value=7;
end : labeled
initial begin #1; if(labeled.local_value!=7) $fatal; $display("PASS"); $finish; end

endmodule
