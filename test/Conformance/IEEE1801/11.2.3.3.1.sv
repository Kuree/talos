// CLAUSE: Immediate write access overview
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
upfSupplyTypeT s;
initial begin
if(!supply_on("/top/VDD",0.8))$fatal(1,"on");
s=get_supply_value("/top/VDD");if(s.state!=FULL_ON || s.voltage!=800000)$fatal(1,"state");
$display("PASS");$finish;end endmodule
