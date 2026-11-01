// CLAUSE: A configuration selects its design root
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 -O3 --execution-tier=%tier --top=cfg %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;initial begin $display("PASS");$finish;end endmodule
config cfg;design work.top;default liblist work;endconfig
