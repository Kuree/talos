// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 6.7: net types resolve conflicting drivers differently (wand 0, wor 1) and tri1/tri0 pull an undriven net to 1/0.
// CHECK: wand=0 wor=1 tri1=1 tri0=0 init=a

module top;
  wand w1;  wor w2;  tri1 t1;  tri0 t0;  wire [3:0] init = 4'hA;
  assign w1 = 1;  assign w1 = 0;
  assign w2 = 0;  assign w2 = 1;
  assign t1 = 1'bz;  assign t0 = 1'bz;
  initial begin #1; $display("wand=%b wor=%b tri1=%b tri0=%b init=%h", w1, w2, t1, t0, init); end
endmodule
