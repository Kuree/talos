// CLAUSE: Relationship objects
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfExtentT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.4/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfExtentT value;endmodule
