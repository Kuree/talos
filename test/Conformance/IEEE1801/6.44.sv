// CLAUSE: set_equivalent
// SINCE: 0.2.0
// REQUIRES: upf
// Pins: declared electrical equivalence joins supply values and suppresses
// own-context output isolation under explicit receiver assumptions (6.44/6.45).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.44/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run q=1
// CHECK: iso q=1

module leaf(input logic iso,output logic q);always_comb q=1;endmodule
module top;
import UPF::*;
logic iso=0;wire q;leaf dut(iso,q);
initial begin
if (!supply_on("/top/dut/VA") || !supply_on("/top/dut/VB") || !supply_on("/top/dut/VSS",0.0))
  $fatal(1,"supplies");
#1;$display("run q=%b",q);
iso=1;#1;$display("iso q=%b",q);
$finish;
end
endmodule
