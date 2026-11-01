// CLAUSE: UPF hierarchy and generate scopes
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a generate scope contributes a path component but is no instance: find_objects returns g/u only, and objects created there are reached through g (IEEE 1801-2018 4.3.6).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.3.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/g/u/rail FULL_ON 900000
// CHECK: on g.u=1 other=1
// CHECK: off g.u=x other=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q,r;if(1)begin:g leaf u(q);end leaf other(r);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/g/u/rail",0.9));
#1;show("/top/g/u/rail");$display("on g.u=%b other=%b",q,r);
void'(supply_off("/top/VDD"));#1;$display("off g.u=%b other=%b",q,r);
$finish;
end
endmodule
