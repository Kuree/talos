// CLAUSE: Supply net
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfSupplyNetT'; did you mean 'upfSupplyTypeT'?
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.8/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfSupplyNetT value;endmodule
