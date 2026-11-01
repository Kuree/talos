// CLAUSE: Implemented UPF objects
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: supply object name conflicts with an HDL object; HDL supply-object reuse is not implemented
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;import UPF::*;supply_net_type rail;endmodule
