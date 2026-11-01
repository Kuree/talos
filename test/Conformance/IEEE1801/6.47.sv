// CLAUSE: set_partial_on_translation
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.47/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=1;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;if(q!==1)$fatal(1,"switch on");
en=0;#1;if(q!==1'bx)$fatal(1,"switch off");
en=1;#1;if(q!==1)$fatal(1,"switch restored");
$display("PASS");$finish;
end
endmodule
