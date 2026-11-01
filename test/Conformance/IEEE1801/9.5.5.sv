// CLAUSE: CORRUPT_ON_CHANGE
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state simstate: CORRUPT_ON_CHANGE
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.5.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;endmodule
