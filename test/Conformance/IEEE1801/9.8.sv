// CLAUSE: Simulation of isolation
// REQUIRES: upf
// XFAIL: *
// Isolation on collapsed output nets is not implemented.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module cluster(output wire q);leaf child(q);endmodule
module top;
import UPF::*;
logic en=1,iso=0;wire q;cluster dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;iso=1;en=0;#1;
if(dut.q!==1'bx || q!==0)$fatal(1,"boundary clamp");
$display("PASS");$finish;
end
endmodule
