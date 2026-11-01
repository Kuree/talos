// CLAUSE: Lists and strings
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: Tcl lists and quoted strings carry multiple names: both listed instances enter the domain (IEEE 1801-2018 5.3.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 111
// CHECK: off xx1
// CHECK: /top/VDD OFF 0
// CHECK: /top/VSS FULL_ON 0

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b,c;leaf u0(a),u1(b),u2(c);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b%b",a,b,c);
void'(supply_off("/top/VDD"));#1;$display("off %b%b%b",a,b,c);
show("/top/VDD");show("/top/VSS");
$finish;
end
endmodule
