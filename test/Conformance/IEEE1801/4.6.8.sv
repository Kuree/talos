// CLAUSE: Power-management cells
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_isolation_cell"; the command is not implemented.
// Pins: a library cell can itself be a power-management cell: defining it changes how its domain corrupts it (IEEE 1801-2018 4.6.8).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.6.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run y=1 z=1
// CHECK: off y=0 z=x

module iso_cell(input logic d,en,output wire y);assign y=d&~en;endmodule
module cluster(input logic en,output wire y,z);iso_cell u(1'b1,en,y);assign z=1;endmodule
module top;
import UPF::*;
logic en=0;wire y,z;cluster dut(en,y,z);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VAON"));
#1;$display("run y=%b z=%b",y,z);
en=1;void'(supply_off("/top/VDD"));#1;$display("off y=%b z=%b",y,z);
$finish;
end
endmodule
