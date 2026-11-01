// CLAUSE: load_upf
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.33/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: LOADED

module leaf;endmodule
module branch;leaf dut();endmodule
module top;branch wrapper();endmodule
