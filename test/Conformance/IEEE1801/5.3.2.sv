// CLAUSE: Identifiers
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: identifiers are case-sensitive: VDD and vdd are two independent nets (IEEE 1801-2018 5.3.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/VDD FULL_ON 900000
// CHECK: /top/vdd OFF 0
// CHECK: /top/V_1 FULL_ON 500000
// CHECK: VDD on q=1
// CHECK: vdd on q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VDD",0.9));void'(supply_off("/top/vdd"));void'(supply_on("/top/V_1",0.5));
#1;show("/top/VDD");show("/top/vdd");show("/top/V_1");$display("VDD on q=%b",q);
void'(supply_off("/top/VDD"));void'(supply_on("/top/vdd"));#1;$display("vdd on q=%b",q);
$finish;
end
endmodule
