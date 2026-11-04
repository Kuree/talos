// RUN: talos -O3 %s -o %t
// RUN: %t > %t.out
// RUN: FileCheck %s < %t.out

// IEEE 1800-2023 21.2.3: the runtime compares a $monitor's arguments once per
// time slot, in its Postponed pass (4.4.2.9). A real argument that stays NaN
// is no change from one slot to the next, a NaN with other bits is one, and
// -0.0 against 0.0 is none (11.4.5). An argument that reads the time keeps
// its subscriptions instead: it is compared when a variable it reads changes,
// not in every slot in which the time moved. A new $monitor replaces the old
// one. The text is what every other tier prints.
module top;
  logic clk = 0;
  logic [7:0] a = 0;
  real r = 1.5;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 1;
  initial begin
    $monitor("nan t=%0t r=%0d", $time, r * 2.0);
    #12 r = $bitstoreal(64'h7ff8000000000000);
    #20 r = $bitstoreal(64'h7ff8000000000001);
    #20 r = -0.0;
    #10 r = 0.0;
    #10 $monitor("time t=%0t q=%0d a=%0d", $time, $time / 4, a);
    #40 $finish;
  end
endmodule

// CHECK: nan t=0 r=3
// CHECK-NEXT: nan t=12 r=nan
// CHECK-NEXT: nan t=32 r=nan
// CHECK-NEXT: nan t=52 r=0
// CHECK-NEXT: time t=72 q=18 a=7
// CHECK-NEXT: time t=75 q=18 a=8
// CHECK-NEXT: time t=85 q=21 a=9
// CHECK-NEXT: time t=95 q=23 a=10
// CHECK-NEXT: time t=105 q=26 a=11
// CHECK-NOT: t=
