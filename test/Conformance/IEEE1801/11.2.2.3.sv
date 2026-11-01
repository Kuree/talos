// CLAUSE: Native HDL representation
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfPowerStateObjT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.2.3/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfPowerStateObjT value;endmodule
