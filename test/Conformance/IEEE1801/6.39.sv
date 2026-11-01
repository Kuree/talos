// CLAUSE: save_upf
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "save_upf"; the command is not implemented.
// Pins: a saved file reproduces the intent: reloading it into a fresh compile simulates like the original (IEEE 1801-2018 6.39).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.39/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf saved.upf -O3 --execution-tier=%tier %s -o %t.saved.exe
// RUN: %t.saved.exe
// CHECK: on dut=1 other=1
// CHECK: off dut=x other=1
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
