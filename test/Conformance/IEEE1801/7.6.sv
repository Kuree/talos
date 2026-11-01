// CLAUSE: define_power_switch_cell
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_power_switch_cell"; the command is not implemented.
// Pins: a defined switch cell drives its switchable pin from its enable expression, and the domain fed by that pin follows the control (IEEE 1801-2018 7.6).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: open q=x
// CHECK: closed q=1
// CHECK: open q=x

module leaf(output wire q);assign q=1;endmodule
module header(input logic en);endmodule
module top;
import UPF::*;
logic en=0;wire q;leaf dut(q);header sw(en);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("open q=%b",q);
en=1;#1;$display("closed q=%b",q);
en=0;#1;$display("open q=%b",q);
$finish;
end
endmodule
