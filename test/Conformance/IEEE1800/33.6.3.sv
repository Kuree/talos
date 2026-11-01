// CLAUSE: A cell clause redirects all matching instances
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 -O3 --execution-tier=%tier --top=cfg --libmap %S/Inputs/33.6.3/map.lib  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;leaf a(),b();initial begin #1;if(a.V!=22||b.V!=22)$fatal(1,"library binding");$display("PASS");$finish;end endmodule
config cfg;design work.top;default liblist fast work;cell leaf use slow.leaf;endconfig
