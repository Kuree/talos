// CLAUSE: Command refinement
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: -update adds to a set, and a conflicting -update fails and keeps the earlier binding; without -update a redeclaration fails (IEEE 1801-2018 5.10).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.10/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/S.power OFF 0
// CHECK: other only q=x
// CHECK: /top/S.power FULL_ON 900000
// CHECK: /top/refused OFF 0
// CHECK: vdd q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/OTHER",0.5));void'(supply_on("/top/VSS",0.0));
#1;show("/top/S.power");$display("other only q=%b",q);
void'(supply_on("/top/VDD",0.9));void'(supply_off("/top/OTHER"));
#1;show("/top/S.power");show("/top/refused");$display("vdd q=%b",q);
$finish;
end
endmodule
