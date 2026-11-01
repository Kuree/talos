// CLAUSE: Any state transition to CORRUPT_ON_CHANGE
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state simstate: CORRUPT_ON_CHANGE; the simstate is not implemented.
// Pins: entering CORRUPT_ON_CHANGE from NORMAL corrupts nothing by itself, unlike CORRUPT, and leaving it with no activity keeps the values (IEEE 1801-2018 9.6.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.6.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run y=1 r=1
// CHECK: entered y=1 r=1
// CHECK: restored y=1 r=1

module leaf(input logic a,b,clk,d,output wire y,output logic r);
assign y=a|b;
always @(posedge clk)r<=d;
endmodule
module top;
import UPF::*;
logic a=1,b=0,clk=0,d=1;wire y,r;leaf dut(a,b,clk,d,y,r);
task automatic low;void'(supply_on("/top/VDD",0.7));#1;endtask
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;clk=1;#1;clk=0;#1;$display("run y=%b r=%b",y,r);
void'(supply_on("/top/VDD",0.7));#1;$display("entered y=%b r=%b",y,r);
void'(supply_on("/top/VDD",1.0));#1;$display("restored y=%b r=%b",y,r);
$finish;
end
endmodule
