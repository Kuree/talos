// CLAUSE: Phase 1 / read power intent specification
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: phase 1 reads commands in order, and an object keeps its execution scope: an -update from another scope fails, and the same update from the declaring scope binds that scope's VDD (IEEE 1801-2018 8.3.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/S.power OFF 0
// CHECK: /top/refused FULL_ON 600000
// CHECK: /top/dut/S.power FULL_ON 900000

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD",1.0));void'(supply_on("/top/refused",0.6));
show("/top/dut/S.power");show("/top/refused");
void'(supply_on("/top/dut/VDD",0.9));
show("/top/dut/S.power");
$finish;
end
endmodule
