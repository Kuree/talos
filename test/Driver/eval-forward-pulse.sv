// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t && %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

// A seed propagates around a feedback loop. A real sensitivity event can
// make the interior writer pulse even when its final value holds (4.6, 9.4.2).
module top;
  bit seed, enable, kick, a, b, c, d;
  int rises, falls;
  always_comb a = seed | d;
  always @(a or kick) begin
    b = 0;
    b = a;
  end
  always_comb c = b;
  always_comb d = c & enable;
  always @(posedge b) rises++;
  always @(negedge b) falls++;
  initial begin
    #1 enable = 1; seed = 1;
    #1 seed = 0;
    #1 $display("held %b%b%b%b %0d %0d", a, b, c, d, rises, falls);
    kick = 1;
    #1 $display("pulse %b%b%b%b %0d %0d", a, b, c, d, rises, falls);
    enable = 0;
    #1 $display("clear %b%b%b%b %0d %0d", a, b, c, d, rises, falls);
    $finish;
  end
endmodule
// CHECK: held 1111 1 0
// CHECK-NEXT: pulse 1111 2 1
// CHECK-NEXT: clear 0000 2 2
