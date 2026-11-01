// CLAUSE: Library notation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier --libmap %S/Inputs/33.2.1/map.lib %s -o %t.exe
// RUN: %t.exe
// Pins 33.2.1: lib.cell notation selects the cell from the named library (y from lb) while x resolves through the default liblist (la).
// CHECK: x=1 y=2

module top;
  leaf x();  leaf y();
  initial begin #1; $display("x=%0d y=%0d", x.P, y.P); end
endmodule
config cfg; design work.top; default liblist la lb; instance top.y use lb.leaf; endconfig
