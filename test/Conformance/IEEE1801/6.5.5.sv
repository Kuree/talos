// CLAUSE: Power expression
// REQUIRES: upf
// XFAIL: *
// begin_power_model is unavailable; the valid model-expression probe cannot reach its property oracle.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.5.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf;endmodule
module top;leaf dut();endmodule
