// CLAUSE: Boolean expressions
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic a=1,b=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;a=0;b=1;#1;if(q!==1)$fatal(1,"aggregate ON");
$display("PASS");$finish;
end
endmodule
