// CLAUSE: Precedence resolution for name affixes
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: "UPF requires a unique elaborated design top", because the uninstantiated cell model counts as a second top; name_format is also not implemented.
// Pins: the strategy's own -name_prefix takes precedence over the global name_format prefix, as seen in the inserted cell's path (IEEE 1801-2018 5.7.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: cell {{.*}}ISO_{{.*}}
// CHECK: run q=1

module iso_mark(input logic d,en,output wire y);assign y=d&~en;initial $display("cell %m");endmodule
module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic iso=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("run q=%b",q);
$finish;
end
endmodule
