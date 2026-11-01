// CLAUSE: create_supply_set overview
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.26.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;import UPF::*;
upfSupplyTypeT a,b;leaf dut();
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
a=get_supply_value("/top/CORE.power");b=get_supply_value("/top/P.primary.power");if(a!==b)$fatal(1,"alias");
$display("PASS");$finish;end endmodule
