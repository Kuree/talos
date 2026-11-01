// CLAUSE: instance use binding
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier --libmap %S/Inputs/33.4.1.3/map.lib %s -o %t.exe
// RUN: %t.exe
// Pins 33.4.1.3: instance clauses bind a single instance (top.b to lb.leaf) or override its parameter (top.m.c gets P=9); other instances keep the default.
// CHECK: a=1 b=2 c=9

module mid; leaf c(); endmodule
module top;
  leaf a();  leaf b();  mid m();
  initial begin #1; $display("a=%0d b=%0d c=%0d", a.P, b.P, m.c.P); end
endmodule
config cfg;
  design work.top;
  default liblist work la lb;
  instance top.b use lb.leaf;
  instance top.m.c use la.leaf #(.P(9));
endconfig
