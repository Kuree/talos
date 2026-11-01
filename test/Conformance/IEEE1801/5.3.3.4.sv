// CLAUSE: Hierarchical names
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a hierarchical name reaches objects below the current scope: connecting dut/VDD to dut/P leaves the same-named top net apart (IEEE 1801-2018 5.3.3.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.3.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/VDD FULL_ON 900000
// CHECK: /top/VDD OFF 0

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/P",0.9));
show("/top/dut/VDD");show("/top/VDD");
$finish;
end
endmodule
