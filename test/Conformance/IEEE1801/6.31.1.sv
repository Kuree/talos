// CLAUSE: find_objects overview
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: the search is non-transitive by default, and -transitive adds the lower match (IEEE 1801-2018 6.31.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.31.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/N2 FULL_ON 600000
// CHECK: on upper=1 lower=1
// CHECK: off upper=x lower=1

module leaf(output wire q);assign q=1;endmodule
module branch(output wire q);leaf child(q);endmodule
module top;
import UPF::*;
wire a,b;leaf child(a);branch dut(b);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/N2",0.6));
#1;show("/top/N2");$display("on upper=%b lower=%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off upper=%b lower=%b",a,b);
$finish;
end
endmodule
