// CLAUSE: Explicit and implicit supply connections
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.4.6.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);upfSupplyTypeT value;
initial begin
void'(supply_on("/top/VSS",0.0));
if(!supply_on("/top/rail"))$fatal;
value=get_supply_value("/top/dut/PAD");if(value.state!=FULL_ON)$fatal(1,"downward supply connection");
#1;if(q!==1)$fatal;
$display("PASS");$finish;
end
endmodule
