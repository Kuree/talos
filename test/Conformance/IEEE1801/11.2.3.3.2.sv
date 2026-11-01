// CLAUSE: upf_set_value_int
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upf_set_value_int'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

module top;import UPF::*;initial void'(upf_set_value_int(0,1));endmodule
