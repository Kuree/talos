// CLAUSE: Error checking
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: an uncaught command error stops compilation with a located diagnostic; a caught one lets the rest of the intent take effect (IEEE 1801-2018 8.4).
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.4/illegal.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on q=1
// CHECK: off q=x
// DIAG: illegal.upf
// DIAG: UPF execution failed

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on q=%b",q);
void'(supply_off("/top/VDD"));#1;$display("off q=%b",q);
$finish;
end
endmodule
