// CLAUSE: Language basics
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: chapter sample: Tcl lists and a command result build the intent, and a caught error commits nothing (IEEE 1801-2018 5.1, 5.3, 5.11).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on dut=1 other=1
// CHECK: off dut=x other=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a),other(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on dut=%b other=%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off dut=%b other=%b",a,b);
$finish;
end
endmodule
