// CLAUSE: set_domain_supply_net (legacy)
// REQUIRES: upf
// XFAIL: *
// switchable domain has no supported state or drivers
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.43/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf;endmodule
module top;leaf dut();endmodule
