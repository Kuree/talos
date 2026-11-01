// CLAUSE: Processing phases
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: the phases take effect in order: a scoped file is read first, and the association it deferred is resolved before simulation (IEEE 1801-2018 8.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/PD.primary.power FULL_ON 900000
// CHECK: on q=1
// CHECK: off q=x

module leaf(output wire q);assign q=1;endmodule
module cluster(output wire q);leaf u(q);endmodule
module top;
import UPF::*;
wire q;cluster dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/rail",0.9));void'(supply_on("/top/dut/VSS",0.0));
show("/top/PD.primary.power");
#1;$display("on q=%b",q);
void'(supply_off("/top/dut/rail"));#1;$display("off q=%b",q);
$finish;
end
endmodule
