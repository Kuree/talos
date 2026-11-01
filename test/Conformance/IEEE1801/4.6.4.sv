// CLAUSE: Logic sources, sinks, and literal supplies
// REQUIRES: upf
// XFAIL: *
// An undriven internal port does not receive the required corrupt-value driver.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.6.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(input wire a,output wire q);assign q=a;endmodule
module top;
import UPF::*;
wire q;leaf dut(.a(),.q(q));
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;if(dut.a!==1'bx || q!==1'bx)$fatal(1,"undriven a=%b q=%b",dut.a,q);
$display("PASS");$finish;
end
endmodule
