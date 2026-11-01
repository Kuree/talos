// CLAUSE: Power state definition restrictions
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: a state of one set may not reference another set's function: the command is rejected and its state never overlaps ON (IEEE 1801-2018 6.5.6).
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.5.6/illegal.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.5.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on q=1
// CHECK: off q=x
// DIAG: cannot reference another supply set's function

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/A.power"));void'(supply_on("/top/A.ground",0.0));void'(supply_on("/top/B.power"));
#1;$display("on q=%b",q);
void'(supply_off("/top/A.power"));#1;$display("off q=%b",q);
$finish;
end
endmodule
