// CLAUSE: HDL access functions
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upf_get_value_int'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

module top;import UPF::*;initial void'(upf_get_value_int(0));endmodule
