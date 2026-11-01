// CLAUSE: Self-contained UPF
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_power_model"; the command is not implemented.
// Pins: self-contained UPF declares everything it needs: the model's own supply port is the only connection the integrator makes (IEEE 1801-2018 4.9.2.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.9.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
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
