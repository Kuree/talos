// CLAUSE: Data requirements
// REQUIRES: upf
// XFAIL: *
// HDL attribute UPF_simstate_behavior is ignored, so the attributed instance is corrupted (off 0xx... simulates off xx instead of off 1x).
// Pins: HDL attributes are required input data: UPF_simstate_behavior on the module takes effect without any UPF command (IEEE 1801-2018 8.2, 6.53).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 11
// CHECK: off 1x

(* UPF_simstate_behavior="DISABLE" *) module leaf(output wire q);assign q=1;endmodule
module plain(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a);plain sib(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off %b%b",a,b);
$finish;
end
endmodule
