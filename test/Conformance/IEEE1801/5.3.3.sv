// CLAUSE: Names
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: one object answers to its simple, hierarchical and dotted names (IEEE 1801-2018 5.3.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/S.power FULL_ON 900000
// CHECK: /top/dut/INNER FULL_ON 700000
// CHECK: /top/S.ground OFF 0

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/RAIL",0.9));void'(supply_on("/top/dut/INNER",0.7));
show("/top/S.power");show("/top/dut/INNER");show("/top/S.ground");
$finish;
end
endmodule
