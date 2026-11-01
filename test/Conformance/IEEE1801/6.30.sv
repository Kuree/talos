// CLAUSE: end_power_model (legacy)
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "begin_power_model"; the command is not implemented.
// Pins: end_power_model closes the model: the next command acts on the design again, in the enclosing scope (IEEE 1801-2018 6.30).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.30/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: after=600000
// CHECK: on dut=1 other=1
// CHECK: off dut=x other=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a),other(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/after",0.6));$display("after=%0d",get_supply_value("/top/after").voltage);
#1;$display("on dut=%b other=%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off dut=%b other=%b",a,b);
$finish;
end
endmodule
