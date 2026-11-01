// CLAUSE: sim_assertion_control
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "sim_assertion_control"; the command is not implemented.
// Pins: the control suspends the assertion in the listed instance while its expression holds: the off-time failures stop being counted (IEEE 1801-2018 6.55).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.55/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on fails=0
// CHECK: end fails=0

module leaf(input logic clk,output wire q,output int fails);
assign q=1;
initial fails=0;
always @(posedge clk) assert(q===1'b1) else fails++;
endmodule
module top;
import UPF::*;
logic clk=0,off=0;wire q;int fails;leaf dut(clk,q,fails);
task automatic tick;clk=1;#1;clk=0;#1;endtask
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;tick;$display("on fails=%0d",fails);
off=1;void'(supply_off("/top/VDD"));#1;tick;tick;
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));off=0;#1;tick;$display("end fails=%0d",fails);
$finish;
end
endmodule
