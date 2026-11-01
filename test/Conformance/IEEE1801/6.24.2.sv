// CLAUSE: Supply net resolution
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: the first UPF slice supports unresolved supply nets
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;endmodule
