// CLAUSE: create_supply_net overview
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: -domain records the declaring domain and -reuse shares that one net with another: a repeat without -reuse fails (IEEE 1801-2018 6.24.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/V FULL_ON 900000
// CHECK: /top/needs_reuse FULL_ON 600000
// CHECK: on 11
// CHECK: off xx

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a),other(b);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/V",0.9));void'(supply_on("/top/needs_reuse",0.6));
#1;show("/top/V");show("/top/needs_reuse");$display("on %b%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off %b%b",a,b);
$finish;
end
endmodule
