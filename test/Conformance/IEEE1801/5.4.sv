// CLAUSE: Boolean expressions
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: Boolean expressions: ! && || with SystemVerilog precedence, and any X/Z operand of an ON expression is unknown even when masked (IEEE 1801-2018 5.4, 6.22).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: 000 q=x
// CHECK: 100 q=1
// CHECK: 010 q=x
// CHECK: 011 q=1
// CHECK: 111 q=1
// CHECK: 1x1 q=x
// CHECK: x00 q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic a=0,b=0,c=0;wire q;leaf dut(q);
task automatic row(logic x,y,z);a=x;b=y;c=z;#1;$display("%b%b%b q=%b",a,b,c,q);endtask
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
row(0,0,0);row(1,0,0);row(0,1,0);row(0,1,1);row(1,1,1);
row(1,1'bx,1);row(1'bx,0,0);
$finish;
end
endmodule
