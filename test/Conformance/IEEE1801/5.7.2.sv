// CLAUSE: Precedence resolution for power domains
// REQUIRES: upf
// XFAIL: *
// nested switchable domains are not implemented: top.Q and top.P
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module leaf;endmodule
module branch;leaf child();endmodule
module top;branch dut();endmodule
