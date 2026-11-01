// CLAUSE: HDL supply ports and nets
// REQUIRES: upf
// XFAIL: *
// HDL-defined supply objects cannot yet be reused by the UPF supply network.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import UPF::*;
supply_net_type rail;
upfSupplyTypeT value;
initial begin
if(!supply_on("/top/rail",1.0))$fatal(1,"HDL-defined supply");
value=get_supply_value("/top/rail");if(value.state!=FULL_ON)$fatal;
$display("PASS");$finish;
end
endmodule
