// CLAUSE: Special characters
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: brackets in an escaped instance name select one array element: only dut[0] gets the net and the domain (IEEE 1801-2018 5.3.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/dut[0]/VDD FULL_ON 900000
// CHECK: on q=11
// CHECK: off q=1x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire [1:0] q;leaf dut[1:0](q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/dut[0]/VDD",0.9));void'(supply_on("/top/dut[0]/VSS",0.0));
show("/top/dut[0]/VDD");
#1;$display("on q=%b",q);
void'(supply_off("/top/dut[0]/VDD"));#1;$display("off q=%b",q);
$finish;
end
endmodule
