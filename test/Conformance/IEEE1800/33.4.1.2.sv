// CLAUSE: Library notation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier --libmap %S/Inputs/33.4.1.2/map.lib %s -o %t.exe
// RUN: %t.exe
// Pins 33.4.1.2: the default liblist (lb first) binds x; the more specific instance liblist (la) overrides it for y.
// CHECK: x=2 y=1

module top;
  leaf x();  leaf y();
  initial begin #1; $display("x=%0d y=%0d", x.P, y.P); end
endmodule
config cfg; design work.top; default liblist lb la; instance top.y liblist la; endconfig
