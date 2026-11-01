// CLAUSE: Successive refinement
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a later file refines the set a first file declared; the first file's voltage constraint still governs the refined supply (IEEE 1801-2018 4.9.1, 5.10).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.9.1/constraints.upf --upf %S/Inputs/4.9.1/implementation.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/CORE.power FULL_ON 1000000
// CHECK: nominal q=1
// CHECK: low q=x
// CHECK: nominal q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;show("/top/CORE.power");$display("nominal q=%b",q);
void'(supply_on("/top/VDD",0.8));#1;$display("low q=%b",q);
void'(supply_on("/top/VDD",1.0));#1;$display("nominal q=%b",q);
$finish;
end
endmodule
