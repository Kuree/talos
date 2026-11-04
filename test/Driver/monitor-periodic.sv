// RUN: talos -O3 %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.err
// RUN: FileCheck %s < %t.out
// RUN: FileCheck %s --check-prefix=DIAG < %t.err

// IEEE 1800-2023 21.2.3: $monitor reports at the end of a time step in which
// one of its arguments (other than $time) changed. The runtime compares the
// arguments once per slot, in its Postponed pass, instead of subscribing to
// every write of them, so the generated periodic loop keeps the clock: it
// ends each slot in its postponed hook and hands a slot to the runtime only
// when the monitor has to report. $monitoroff suspends reporting and
// $monitoron reports at once. The text is what every other tier prints.
module top;
  logic clk = 0;
  logic [7:0] a = 0;
  logic [7:0] b = 3;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 1;
  initial begin
    $monitor("t=%0t a=%0d b=%0d", $time, a[7:1], b);
    #47 b = 9;
    #20 $monitoroff;
    #30 $monitoron;
    #30 $finish;
  end
endmodule

// CHECK: t=0 a=0 b=3
// CHECK-NEXT: t=15 a=1 b=3
// CHECK-NEXT: t=35 a=2 b=3
// CHECK-NEXT: t=47 a=2 b=9
// CHECK-NEXT: t=55 a=3 b=9
// CHECK-NEXT: t=97 a=5 b=9
// CHECK-NEXT: t=115 a=6 b=9
// CHECK-NOT: t=

// The loop kept the clock: it is prepared once per runtime deadline and per
// monitor report, never left to the generic scheduler.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations=8
