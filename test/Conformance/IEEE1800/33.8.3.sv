// CLAUSE: An exact file match takes precedence over a wildcard
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 -O3 --execution-tier=%tier --top=cfg --libmap %S/Inputs/33.8.3/map.lib %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;leaf d();initial begin #1;if(d.V!=7)$fatal(1,"path binding");$display("PASS");$finish;end endmodule
config cfg;design work.top;default liblist selected work;endconfig
