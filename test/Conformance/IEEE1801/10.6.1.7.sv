// CLAUSE: Named object reference
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfNamedRefT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.7/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfNamedRefT value;endmodule
