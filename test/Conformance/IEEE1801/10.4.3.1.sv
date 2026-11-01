// CLAUSE: HDL relationships in the information model
// REQUIRES: upf
// XFAIL: *
// Required information-model queries are unavailable; the semantic assertion cannot yet be reached.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf;endmodule
module top;leaf dut();endmodule
