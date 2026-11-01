// CLAUSE: create_upf2hdl_vct
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_upf2hdl_vct"; the command is not implemented.
// Pins: a user table defines the conversion, here unlike any predefined one (IEEE 1801-2018 6.27).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.27/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: OFF 1
// CHECK: FULL_ON 0
// CHECK: PARTIAL_ON 1
// CHECK: UNDETERMINED 0

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
