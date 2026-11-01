// CLAUSE: Power architecture
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic a=1,b=1;wire x,y;leaf dut(x),other(y);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;a=0;#1;if(x!==1'bx || y!==1)$fatal(1,"domain ownership");
$display("PASS");$finish;
end
endmodule
