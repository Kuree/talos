// CLAUSE: upf_version
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: upf_version returns the running version, with or without an argument, and refuses any other version (IEEE 1801-2018 6.58).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.58/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/V3_1 FULL_ON 900000
// CHECK: /top/current3_1 FULL_ON 700000
// CHECK: /top/refused FULL_ON 600000

module leaf;endmodule
module top;
import UPF::*;
leaf dut();
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/V3_1",0.9));void'(supply_on("/top/current3_1",0.7));void'(supply_on("/top/refused",0.6));
show("/top/V3_1");show("/top/current3_1");show("/top/refused");
$finish;
end
endmodule
