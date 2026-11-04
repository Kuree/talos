// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.err
// RUN: FileCheck %s < %t.out
// RUN: FileCheck %s --check-prefix=DIAG < %t.err

// IEEE 1800-2023 21.2.3: the runtime compares a $monitor's arguments once per
// time slot, at the end of each slot of the generated periodic loop (4.4.2.9).
// A real argument that stays NaN is no change from one slot to the next, a
// NaN with other bits is one, and -0.0 against 0.0 is none (11.4.5). The
// text is what every other tier prints.
module top;
  logic clk = 0;
  logic [7:0] a = 0;
  logic [63:0] w = 64'h3ff8000000000000;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 1;
  initial begin
    $monitor("nan t=%0t r=%0d", $time, $bitstoreal(w));
    #12 w = 64'h7ff8000000000000;
    #20 w = 64'h7ff8000000000001;
    #20 w = 64'h8000000000000000;
    #10 w = 64'h0;
    #50 $finish;
  end
endmodule

// CHECK: nan t=0 r=2
// CHECK-NEXT: nan t=12 r=nan
// CHECK-NEXT: nan t=32 r=nan
// CHECK-NEXT: nan t=52 r=0
// CHECK-NOT: t=

// The loop kept the clock while the NaN monitor was on.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations={{[1-9]}}
