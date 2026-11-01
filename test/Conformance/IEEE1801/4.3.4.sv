// CLAUSE: HDL scopes
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a command acts in the current HDL scope; set_scope returns the previous one (IEEE 1801-2018 4.3.4, 6.52).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.3.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/rail FULL_ON 900000
// CHECK: /top/rail OFF 0
// CHECK: /top/back FULL_ON 700000

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/rail",0.9));void'(supply_on("/top/back",0.7));
show("/top/dut/rail");show("/top/rail");show("/top/back");
$finish;
end
endmodule
