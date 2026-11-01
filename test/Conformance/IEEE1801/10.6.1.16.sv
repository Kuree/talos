// CLAUSE: Supply port state
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfSupplyPortStateT'; did you mean 'upfSupplyStateE'?
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.16/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfSupplyPortStateT value;endmodule
