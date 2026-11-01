// CLAUSE: Phase 5 / query power intent model
// REQUIRES: upf
// XFAIL: *
// This IEEE 1801 command is not registered by the UPF interpreter.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.3.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;endmodule
