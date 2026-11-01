// CLAUSE: General treatment of precedence
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-no_isolation' in set_isolation
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module leaf(output logic q=0);endmodule
module top;logic iso=0;wire q;leaf dut(q);endmodule
