// CLAUSE: bind_checker
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "bind_checker"; the command is not implemented.
// Pins: bind_checker instantiates the checker in the listed instance, with its port bound to a design signal, so it runs without appearing in the HDL (IEEE 1801-2018 6.12).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.12/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: checker top.dut.CHECKER d=1
// CHECK: checker top.dut.CHECKER d=0

module chk(input logic d);always @(d)$display("checker %m d=%b",d);endmodule
module leaf(input logic d);endmodule
module top;
logic d=0;leaf dut(d);
initial begin
#1;d=1;#1;d=0;#1;
$finish;
end
endmodule
