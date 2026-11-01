// CLAUSE: Type-dependent corruption values
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.5.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(input clk,output logic [3:0] q=4'ha,output bit [3:0] b=5);
always @(posedge clk)begin q<=4'ha;b<=5;end
endmodule
module top;
import UPF::*;
logic clk=0;wire[3:0]q;wire[3:0]b;leaf dut(clk,q,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;clk=1;#1;clk=0;if(q!==4'ha || b!==5)$fatal;
void'(supply_off("/top/VDD"));#1;if(q!==4'bxxxx || b!==0)$fatal(1,"type default corruption");
$display("PASS");$finish;
end
endmodule
