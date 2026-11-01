// CLAUSE: upf_get_label_upfSupplyTypeT
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upf_get_label_upfSupplyTypeT'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.2.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

module top;import UPF::*;initial void'(upf_get_label_upfSupplyTypeT(0));endmodule
