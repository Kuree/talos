// CLAUSE: Simple names
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a simple name resolves in the current scope: the set in dut binds dut's RAIL, not the same-named net above it (IEEE 1801-2018 5.3.3.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/S.power OFF 0
// CHECK: /top/dut/S.power FULL_ON 900000
// CHECK: /top/RAIL FULL_ON 1000000

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/RAIL",1.0));show("/top/dut/S.power");
void'(supply_on("/top/dut/RAIL",0.9));show("/top/dut/S.power");show("/top/RAIL");
$finish;
end
endmodule
