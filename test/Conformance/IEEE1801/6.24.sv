// CLAUSE: create_supply_net
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import UPF::*;
upfSupplyTypeT value;
initial begin
value=get_supply_value("/top/rail");if(value.state!=OFF)$fatal(1,"initial root driver");
if(!supply_on("/top/rail",1.0))$fatal;
value=get_supply_value("/top/rail");if(value.state!=FULL_ON)$fatal;
if(!supply_off("/top/rail"))$fatal;
value=get_supply_value("/top/rail");if(value.state!=OFF)$fatal;
$display("PASS");$finish;
end
endmodule
