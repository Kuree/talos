// CLAUSE: Lexical elements
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: lexical sample: comments, line continuation, and case-distinct identifiers (IEEE 1801-2018 5.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/VDD OFF 0
// CHECK: lower only q=x
// CHECK: upper q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/vdd",0.7));void'(supply_on("/top/VSS",0.0));
#1;show("/top/VDD");$display("lower only q=%b",q);
void'(supply_on("/top/VDD"));#1;$display("upper q=%b",q);
$finish;
end
endmodule
