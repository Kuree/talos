// CLAUSE: Power management
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=1;wire q;leaf dut(q);upfSupplyTypeT s;
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;s=get_supply_value("/top/SW.power");
if(q!==1 || s.state!=PARTIAL_ON)$fatal(1,"partial translation");
$display("PASS");$finish;
end
endmodule
