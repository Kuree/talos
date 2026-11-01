// CLAUSE: Representing SystemC design for power analysis
// REQUIRES: upf
// XFAIL: *
// the compiler has no SystemC frontend: unknown argument '--systemc'.
// Pins: a SystemC module instance is a design element the power intent applies to: it powers and corrupts like HDL (IEEE 1801-2018 4.3.10).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.3.10/design.upf -O3 --execution-tier=%tier --systemc %S/Inputs/4.3.10/leaf.cpp %s -o %t.exe
// RUN: %t.exe
// CHECK: on dut=1 other=1
// CHECK: off dut=x other=1

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
