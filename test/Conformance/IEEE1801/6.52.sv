// CLAUSE: set_scope
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.52/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf;endmodule
module top;
import UPF::*;
leaf dut();upfSupplyTypeT value;
initial begin
if(!supply_on("/top/dut/rail"))$fatal(1,"scope not applied");
value=get_supply_value("/top/dut/rail");if(value.state!=FULL_ON)$fatal;
$display("PASS");$finish;
end
endmodule
