// CLAUSE: CORRUPT_STATE_ON_CHANGE
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state simstate: CORRUPT_STATE_ON_CHANGE; the simstate is not implemented.
// Pins: CORRUPT_STATE_ON_CHANGE: combinational logic still works; a clock edge corrupts only a register whose next state differs (IEEE 1801-2018 9.5.6).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.5.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run y=1 r=1
// CHECK: entered y=1 r=1
// CHECK: same r=1
// CHECK: comb y=0
// CHECK: change r=x

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
clk=1;#1;clk=0;#1;$display("same r=%b",r);
a=0;#1;$display("comb y=%b",y);
d=0;clk=1;#1;clk=0;#1;$display("change r=%b",r);
$finish;
end
endmodule
