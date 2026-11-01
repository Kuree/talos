// CLAUSE: Transitive TRUE
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-exclude_elements' in create_power_domain
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.9.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module leaf;endmodule
module branch;leaf child();endmodule
module top;branch dut(),other();endmodule
