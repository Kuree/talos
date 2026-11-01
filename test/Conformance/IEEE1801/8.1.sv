// CLAUSE: Immediate and deferred UPF effects
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: immediate: set_scope affects the very next command. Deferred: a set associated before its functions exist still powers the domain (IEEE 1801-2018 8.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/rail FULL_ON 900000
// CHECK: /top/rail OFF 0
// CHECK: on q=1
// CHECK: off q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/rail",0.9));
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
show("/top/dut/rail");show("/top/rail");
#1;$display("on q=%b",q);
void'(supply_off("/top/VDD"));#1;$display("off q=%b",q);
$finish;
end
endmodule
