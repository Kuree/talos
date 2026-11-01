// CLAUSE: create_supply_net overview
// REQUIRES: upf
// XFAIL: *
// switchable domain has no supported state or drivers
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child;endmodule
module top;child dut(),other();endmodule
