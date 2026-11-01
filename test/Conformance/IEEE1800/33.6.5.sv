// CLAUSE: An instance can select a nested configuration
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 -O3 --execution-tier=%tier --top=cfg --libmap %S/Inputs/33.6.5/map.lib  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;leaf a(),b();initial begin #1;if(a.V!=11||b.V!=22)$fatal(1,"library binding");$display("PASS");$finish;end endmodule
config cfg;design work.top;default liblist fast work;instance top.b use work.inner:config;endconfig
config inner;design slow.leaf;default liblist slow work;endconfig
