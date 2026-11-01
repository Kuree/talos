// CLAUSE: Pattern matching and wildcarding
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: ? matches one character and * any run within one component; neither crosses a hierarchy separator without -transitive (IEEE 1801-2018 6.31.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.31.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 1111
// CHECK: off xx11

module leaf(output wire q);assign q=1;endmodule
module branch(output wire q);leaf u3(q);endmodule
module top;
import UPF::*;
wire a,b,c,d;leaf u1(a),u2(b),u10(c);branch dut(d);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b%b%b",a,b,c,d);
void'(supply_off("/top/VDD"));#1;$display("off %b%b%b%b",a,b,c,d);
$finish;
end
endmodule
