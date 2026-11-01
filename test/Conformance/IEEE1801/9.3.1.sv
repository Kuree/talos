// CLAUSE: Supply state and power state control
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'set_power_state'; the HDL power-state control function is not implemented.
// Pins: supply control and power-state control combine: set_power_state corrupts while the supply stays on, and supply_off corrupts in any state (IEEE 1801-2018 9.3.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on q=1
// CHECK: /top/VDD FULL_ON 1000000
// CHECK: RET q=x
// CHECK: ON q=1
// CHECK: /top/VDD OFF 0
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
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on q=%b",q);
void'(set_power_state("/top/CORE","RET"));#1;show("/top/VDD");$display("RET q=%b",q);
void'(set_power_state("/top/CORE","ON"));#1;$display("ON q=%b",q);
void'(supply_off("/top/VDD"));#1;show("/top/VDD");$display("off q=%b",q);
$finish;
end
endmodule
