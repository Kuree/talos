// CLAUSE: CORRUPT_STATE_ON_ACTIVITY
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state simstate: CORRUPT_STATE_ON_ACTIVITY; the simstate is not implemented.
// Pins: CORRUPT_STATE_ON_ACTIVITY: combinational logic still works; any clock edge corrupts the register, even when its next state is the same (IEEE 1801-2018 9.5.7).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.5.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run y=1 r=1
// CHECK: entered y=1 r=1
// CHECK: comb y=0 r=1
// CHECK: edge r=x

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
low;$display("entered y=%b r=%b",y,r);
a=0;#1;$display("comb y=%b r=%b",y,r);
clk=1;#1;clk=0;#1;$display("edge r=%b",r);
$finish;
end
endmodule
