// CLAUSE: Power state changes
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VDD",0.8));
#1;if(q!==1'bx)$fatal(1,"undervoltage");
void'(supply_on("/top/VDD",1.0));#1;if(q!==1)$fatal(1,"nominal voltage");
$display("PASS");$finish;
end
endmodule
