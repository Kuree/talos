// CLAUSE: set_design_top
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: set_design_top names the module a file is written for, without moving the scope: relative names in that file still resolve under the loading instance (IEEE 1801-2018 6.42, 4.3.7).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.42/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut/named FULL_ON 700000
// CHECK: /top/dut/rejected FULL_ON 600000
// CHECK: on u=1 parent=1
// CHECK: off u=x parent=1

module leaf(output wire q);assign q=1;endmodule
module cluster(output wire a,b);leaf u(a);assign b=1;endmodule
module top;
import UPF::*;
wire a,b;cluster dut(a,b);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut/VDD"));void'(supply_on("/top/dut/VSS",0.0));
void'(supply_on("/top/dut/named",0.7));void'(supply_on("/top/dut/rejected",0.6));
show("/top/dut/named");show("/top/dut/rejected");
#1;$display("on u=%b parent=%b",a,b);
void'(supply_off("/top/dut/VDD"));#1;$display("off u=%b parent=%b",a,b);
$finish;
end
endmodule
