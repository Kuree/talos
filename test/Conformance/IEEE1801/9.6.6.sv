// CLAUSE: Any state transition to CORRUPT_STATE_ON_ACTIVITY
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state simstate: CORRUPT_STATE_ON_ACTIVITY
// Prerequisite: The required CORRUPT_STATE_ON_ACTIVITY declaration is a prerequisite to exercising this transition.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.6.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;endmodule
