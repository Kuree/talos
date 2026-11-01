// CLAUSE: Generic UPF command semantics
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: "UPF requires a unique elaborated design top", because the uninstantiated cell model counts as a second top; map_power_switch is also not implemented.
// Pins: generic commands state intent independently of implementation: mapping to a cell adds its model, and the output follows the same control (IEEE 1801-2018 5.8).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: mapped {{.*}}
// CHECK: open q=x
// CHECK: closed q=1

module sw_model(input logic ctl);initial $display("mapped %m");endmodule
module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("open q=%b",q);
en=1;#1;$display("closed q=%b",q);
$finish;
end
endmodule
