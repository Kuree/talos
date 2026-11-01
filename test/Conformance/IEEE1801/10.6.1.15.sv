// CLAUSE: Power switch state
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upfPowerSwitchStateT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.15/empty.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;upfPowerSwitchStateT value;endmodule
