// CLAUSE: set_power_state_by_handle
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'set_power_state_by_handle'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

module top;import UPF::*;initial void'(set_power_state_by_handle(0,0));endmodule
