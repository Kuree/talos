// CLAUSE: Handle ID or UPF handle
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfHandleT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfHandleT value;endmodule
