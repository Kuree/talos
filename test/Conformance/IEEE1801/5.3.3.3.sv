// CLAUSE: Dotted names
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a dotted name selects one function of a set: T.power joins S.power, and T.ground does not (IEEE 1801-2018 5.3.3.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.3.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/T.power FULL_ON 900000
// CHECK: /top/T.ground OFF 0
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
void'(supply_on("/top/S.power",0.9));
show("/top/T.power");show("/top/T.ground");show("/top/S.ground");
$finish;
end
endmodule
