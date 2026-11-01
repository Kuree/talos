// CLAUSE: Value conversion tables
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_hdl2upf_vct"
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/B/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;endmodule
