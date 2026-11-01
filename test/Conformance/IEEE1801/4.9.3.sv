// CLAUSE: File structure
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a scoped UPF file is written relative to its instance, and the parent file's scope is unchanged after it (IEEE 1801-2018 4.9.3, 6.33).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.9.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/after FULL_ON 600000
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
void'(supply_on("/top/dut/VDD"));void'(supply_on("/top/dut/VSS",0.0));void'(supply_on("/top/after",0.6));
show("/top/after");
#1;$display("on u=%b parent=%b",a,b);
void'(supply_off("/top/dut/VDD"));#1;$display("off u=%b parent=%b",a,b);
$finish;
end
endmodule
