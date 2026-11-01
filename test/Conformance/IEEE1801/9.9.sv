// CLAUSE: Simulation of level-shifting
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_level_shifter"
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module leaf(output logic q=0);endmodule
module top;wire q;leaf dut(q);endmodule
