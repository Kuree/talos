// CLAUSE: Supply set
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfSupplySetT'; did you mean 'upfSupplyStateE'?
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.6/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfSupplySetT value;endmodule
