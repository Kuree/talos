// CLAUSE: Logic expression
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state option: -logic_expr
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.5.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;logic en=1;endmodule
