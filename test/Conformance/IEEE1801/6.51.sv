// CLAUSE: set_retention_elements
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_retention_elements"; the command is not implemented.
// Pins: a named retention list selects the retained registers: the listed one comes back and the other does not (IEEE 1801-2018 6.51).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.51/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: back a=1 b=x

module regs(input logic clk,output logic a=0,b=0);always @(posedge clk)begin a<=1;b<=1;end endmodule
module top;
import UPF::*;
logic clk=0,rtc=0;wire a,b;regs dut(clk,a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRET"));
#1;clk=1;#1;rtc=1;void'(supply_off("/top/VDD"));#1;void'(supply_on("/top/VDD"));#1;
$display("back a=%b b=%b",a,b);
$finish;
end
endmodule
