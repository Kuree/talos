// CLAUSE: UPF_GNDZERO2SV_LOGIC
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-vct' in connect_supply_net; the option is not implemented.
// Pins: the ground table inverts: FULL_ON is logic 0 and OFF is logic 1 (IEEE 1801-2018 B.9).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/B.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: OFF 1
// CHECK: FULL_ON 0
// CHECK: PARTIAL_ON x
// CHECK: UNDETERMINED x

module sink(input logic vdd);endmodule
module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=0,part=0;wire q;leaf dut(q);sink load(1'bx);
task automatic row(logic e,p);upfSupplyTypeT s;en=e;part=p;#1;s=get_supply_value("/top/VSW");$display("%s %b",s.state.name(),load.vdd);endtask
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
row(1'b0,1'b0);row(1'b1,1'b0);row(1'b0,1'b1);row(1'bx,1'b0);
$finish;
end
endmodule
