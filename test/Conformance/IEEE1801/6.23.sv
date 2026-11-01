// CLAUSE: create_pst (legacy)
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_pst"; the command is not implemented.
// Pins: create_pst names the supplies of its table: a supply that does not exist is refused (IEEE 1801-2018 6.23).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.23/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/checked FULL_ON 600000
// CHECK: on q=1
// CHECK: off q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/checked",0.6));
#1;show("/top/checked");$display("on q=%b",q);
void'(supply_off("/top/VDD"));#1;$display("off q=%b",q);
$finish;
end
endmodule
