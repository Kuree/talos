// CLAUSE: Wildcarding examples
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: worked forms: a search rooted below the scope returns scope-relative names, and -object_type port counts only ports (IEEE 1801-2018 6.31.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.31.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/P3 FULL_ON 600000
// CHECK: on 1111
// CHECK: off xx11

module leaf(output wire q);assign q=1;endmodule
module sub(output wire q);leaf inner(q);endmodule
module branch(output wire a,b,c);leaf x(a);sub s(b);assign c=1;endmodule
module top;
import UPF::*;
wire a,b,c,d;branch dut(a,b,c);leaf other(d);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/P3",0.6));
#1;show("/top/P3");$display("on %b%b%b%b",a,b,c,d);
void'(supply_off("/top/VDD"));#1;$display("off %b%b%b%b",a,b,c,d);
$finish;
end
endmodule
