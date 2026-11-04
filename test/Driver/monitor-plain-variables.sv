// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.err
// RUN: FileCheck %s < %t.out
// RUN: FileCheck %s --check-prefix=DIAG < %t.err

// IEEE 1800-2023 21.2.3, 4.4.2.9: a $monitor whose arguments are plain
// variables waits on observers of them like any other monitor, so the
// generated periodic loop keeps the clock and the runtime compares the
// arguments at the end of each slot. k is written every cycle but changes
// rarely; j changes only when k is 1. The text is what every other tier
// prints.
module top;
  logic clk = 0;
  logic [7:0] a = 0, k = 0, j = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 1;
  always_ff @(posedge clk) k <= {7'b0, a[2] & a[1]};
  always_ff @(posedge clk) if (k[0]) j <= j + 1;
  initial begin
    $monitor("t=%0t k=%0d j=%0d", $time, k, j);
    #100 $finish;
  end
endmodule

// CHECK: t=0 k=0 j=0
// CHECK-NEXT: t=65 k=1 j=0
// CHECK-NEXT: t=75 k=1 j=1
// CHECK-NEXT: t=85 k=0 j=2
// CHECK-NOT: t=

// The loop kept the clock: it is prepared once per runtime deadline and per
// monitor report, never left to the generic scheduler.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations={{[1-9]}}
