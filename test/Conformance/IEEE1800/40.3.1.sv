// CLAUSE: predefined constants
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module device;timeunit 1ns;timeprecision 1ns;bit q=0;task set(input bit v);q=v;endtask endmodule
module top;timeunit 1ns;timeprecision 1ns;device dut();int maximum,current,prior_value,rc;
initial begin
if(`SV_COV_START!=0 || `SV_COV_STOP!=1 || `SV_COV_RESET!=2 || `SV_COV_CHECK!=3 || `SV_COV_MODULE!=10 || `SV_COV_HIER!=11 || `SV_COV_STATEMENT!=22 || `SV_COV_TOGGLE!=23 || `SV_COV_ERROR!=-1)$fatal(1,"coverage constants");
$display("PASS");$finish;end endmodule
