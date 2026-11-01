// CLAUSE: supply_partial_on
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'supply_partial_on'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
initial begin
if(!supply_partial_on("/top/VDD",0.8))$fatal(1,"partial write");
if(get_supply_state(get_supply_value("/top/VDD"))!=PARTIAL_ON)$fatal(1,"partial state");
$display("PASS");$finish;end endmodule
