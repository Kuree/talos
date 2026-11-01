// CLAUSE: Multi-bit representation of complex HDL objects
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfHdlPortMultiBitT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.3.2/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfHdlPortMultiBitT value;endmodule
