// CLAUSE: supply_off
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
upfSupplyTypeT s;
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
if(!supply_off("/top/VDD"))$fatal(1,"off");
s=get_supply_value("/top/VDD");if(s.state!=OFF)$fatal(1,"state");
$display("PASS");$finish;end endmodule
