// CLAUSE: Physical design structure
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: find_objects selects a physical instance, and only that instance is powered by the domain built from its result (IEEE 1801-2018 4.2, 6.31).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
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
