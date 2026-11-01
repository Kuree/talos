// CLAUSE: Supply subnets
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
upfSupplyTypeT s;
initial begin
if(!supply_on("/top/P",0.9))$fatal(1,"source");
s=get_supply_value("/top/Q");if(s.state!=FULL_ON || s.voltage!=900000)$fatal(1,"load");
$display("PASS");$finish;end endmodule
