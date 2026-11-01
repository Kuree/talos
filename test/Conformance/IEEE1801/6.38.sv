// CLAUSE: name_format
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: "UPF requires a unique elaborated design top", because the uninstantiated cell model counts as a second top; name_format is also not implemented.
// Pins: name_format affixes appear in the name of each inserted cell, which its %m shows (IEEE 1801-2018 6.38).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.38/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: cell {{.*}}FMT_{{.*}}_END
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
