// CLAUSE: SystemC language basic
// REQUIRES: upf
// XFAIL: *
// the compiler has no SystemC frontend: unknown argument '--systemc'.
// Pins: UPF names resolve into a SystemC module, whose instance enters a domain by name (IEEE 1801-2018 5.13).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.13/design.upf -O3 --execution-tier=%tier --systemc %S/Inputs/5.13/leaf.cpp %s -o %t.exe
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
