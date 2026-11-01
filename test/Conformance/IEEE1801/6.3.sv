// CLAUSE: add_parameter
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-parameters' in load_upf; add_parameter is not implemented either.
// Pins: a parameter has a default that load_upf -parameters can override, and the file's intent uses its value: the override selects the instance in the domain (IEEE 1801-2018 6.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
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
