// CLAUSE: load_upf_protected (deprecated)
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "load_upf_protected"; the command is not implemented.
// Pins: the protected load runs the file in its scope, and -hide_globals keeps the caller's variable out of it (IEEE 1801-2018 6.34).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.34/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on u=1 parent=1
// CHECK: off u=x parent=1

module leaf(output wire q);assign q=1;endmodule
module cluster(output wire a,b);leaf u(a);assign b=1;endmodule
module top;
import UPF::*;
wire a,b;cluster dut(a,b);
initial begin
void'(supply_on("/top/dut/VDD"));void'(supply_on("/top/dut/VSS",0.0));
#1;$display("on u=%b parent=%b",a,b);
void'(supply_off("/top/dut/VDD"));#1;$display("off u=%b parent=%b",a,b);
$finish;
end
endmodule
