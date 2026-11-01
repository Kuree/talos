// CLAUSE: Supply network initialization
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.2.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
upfSupplyTypeT s;
initial begin
s=get_supply_value("/top/S.power");if(s.state!=OFF)$fatal(1,"initial");
if(!supply_on("/top/S.power"))$fatal(1,"write");
s=get_supply_value("/top/S.power");if(s.state!=FULL_ON)$fatal(1,"implicit root");
$display("PASS");$finish;end endmodule
