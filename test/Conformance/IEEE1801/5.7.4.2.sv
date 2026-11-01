// CLAUSE: Granularity-based precedence resolution
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-elements' in set_isolation
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.4.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module leaf(output logic q=0);endmodule
module top;logic iso=0;wire q;leaf dut(q);endmodule
