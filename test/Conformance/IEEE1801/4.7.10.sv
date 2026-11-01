// CLAUSE: Power state transitions
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "add_state_transition"; the command is not implemented.
// Pins: with a complete transition list, a transition outside it is reported (IEEE 1801-2018 4.7.10).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.10/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[Ii]llegal.*transition|transition.*[Ii]llegal}}
// CHECK-DAG: LO q=1
// CHECK-DAG: up q=1
// CHECK-DAG: down q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VDD",0.8));
#1;$display("LO q=%b",q);
void'(supply_on("/top/VDD",1.0));#1;$display("up q=%b",q);
void'(supply_on("/top/VDD",0.8));#1;$display("down q=%b",q);
$finish;
end
endmodule
