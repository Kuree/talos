// CLAUSE: sim_replay_control
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "sim_replay_control"; the command is not implemented.
// Pins: a marked initial block replays at power-up and restores its value; without the mark the variable stays corrupt (IEEE 1801-2018 6.57).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.57/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on marked=1 plain=1
// CHECK: off marked=x plain=x
// CHECK: back marked=1 plain=x

module leaf(output logic marked,output logic plain);initial marked=1;endmodule
module other(output logic plain);initial plain=1;endmodule
module top;
import UPF::*;
wire a,b,c;leaf dut(a,c);other sib(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on marked=%b plain=%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off marked=%b plain=%b",a,b);
void'(supply_on("/top/VDD"));#1;$display("back marked=%b plain=%b",a,b);
$finish;
end
endmodule
