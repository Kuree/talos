// CLAUSE: Complex HDL signals as bit vectors
// REQUIRES: upf
// XFAIL: *
// Required information-model queries are unavailable; the semantic assertion cannot yet be reached.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct packed {logic[1:0]a;logic[2:0]b;} pair;
wire pair signal_value;
endmodule
