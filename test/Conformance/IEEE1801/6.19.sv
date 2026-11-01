// CLAUSE: create_logic_port
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_logic_port"; the command is not implemented.
// Pins: a UPF-created logic port on an instance takes the value connected to it, and the strategy uses that port as its control (IEEE 1801-2018 6.19).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.19/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: ctl=0 q=1
// CHECK: ctl=1 q=0
// CHECK: ctl=0 q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic ctl=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("ctl=0 q=%b",q);
ctl=1;void'(supply_off("/top/VDD"));#1;$display("ctl=1 q=%b",q);
ctl=0;#1;$display("ctl=0 q=%b",q);
$finish;
end
endmodule
