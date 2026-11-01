// CLAUSE: Default binding follows library-map order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --libmap %S/Inputs/33.6.1/map.lib  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;leaf a(),b();initial begin #1;if(a.V!=11||b.V!=11)$fatal(1,"library binding");$display("PASS");$finish;end endmodule
