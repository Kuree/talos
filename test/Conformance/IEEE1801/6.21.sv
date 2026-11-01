// CLAUSE: create_power_state_group
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_power_state_group"; the command is not implemented.
// Pins: a group's illegal combination is reported when both members reach it, and a legal combination is not (IEEE 1801-2018 6.21).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.21/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[Ii]llegal}}
// CHECK-DAG: A only 1x
// CHECK-DAG: both 11

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a),other(b);
initial begin
void'(supply_on("/top/A.power"));void'(supply_on("/top/A.ground",0.0));void'(supply_on("/top/B.ground",0.0));
#1;$display("A only %b%b",a,b);
void'(supply_on("/top/B.power"));#1;$display("both %b%b",a,b);
$finish;
end
endmodule
