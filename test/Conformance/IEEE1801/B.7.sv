// CLAUSE: UPF2SV_LOGIC
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_port_attributes"
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/B.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top(input logic p);endmodule
