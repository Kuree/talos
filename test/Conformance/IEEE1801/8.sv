// CLAUSE: UPF processing
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: chapter sample: UPF runs after elaboration, so it sees a parameter-selected generate branch; the domain it builds then governs simulation (IEEE 1801-2018 8.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 11
// CHECK: off x1

module leaf(output wire q);assign q=1;endmodule
module top #(parameter int N=2);
import UPF::*;
wire a,b;
if(N==1)begin:one leaf u(a);end else begin:many leaf u(a);end
leaf other(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off %b%b",a,b);
$finish;
end
endmodule
