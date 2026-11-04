// RUN: talos -O3 %s -o %t
// RUN: %t > %t.out
// RUN: FileCheck %s < %t.out

// IEEE 1800-2023 21.2.3: a $monitor argument that reads the time keeps its
// subscriptions: it is compared when a variable it reads changes, not in every
// slot in which the time moved. The text is what every other tier prints.
module top;
  logic clk = 0;
  logic [7:0] a = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 1;
  initial begin
    #2 $monitor("t=%0t q=%0d a=%0d", $time, $time / 4, a);
    #40 $finish;
  end
endmodule

// CHECK: t=2 q=0 a=0
// CHECK-NEXT: t=5 q=1 a=1
// CHECK-NEXT: t=15 q=3 a=2
// CHECK-NEXT: t=25 q=6 a=3
// CHECK-NEXT: t=35 q=8 a=4
// CHECK-NOT: t=
