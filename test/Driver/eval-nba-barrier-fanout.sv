// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.queue
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t.queue > %t.out 2> %t.diag && FileCheck %s < %t.out && FileCheck %s --check-prefix=FIFO < %t.diag
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.clocked && %t.clocked | diff -u %t.out -
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic -DLATE_WAITER %s -o %t.mixed && %t.mixed > %t.mixed.out && FileCheck %s --check-prefix=LATE < %t.mixed.out
// RUN: talos -O0 --execution-tier=bytecode -DLATE_WAITER %s -o %t.mixed.ref && %t.mixed.ref | diff -u %t.mixed.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic -DBIT_REGISTER %s -o %t.bit && env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t.bit > %t.bit.out 2> %t.bit.diag && diff -u %t.out %t.bit.out && FileCheck %s --check-prefix=FIFO < %t.bit.diag

module top;
  logic clk = 0, mirror;
`ifdef BIT_REGISTER
  bit q;
`else
  logic q = 0;
`endif
  int rises;
  always #5 clk = !clk;
  always_ff @(posedge clk) q <= !q;
  always_comb mirror = q;
  always @(posedge mirror) rises++;
`ifdef LATE_WAITER
  // Arm after the first FIFO update, then leave the wait before the third.
  logic captured;
  initial begin
    #11;
    @(q) captured = q;
  end
`endif
  initial begin
    @(posedge clk);
    #0 $display("inactive q=%b mirror=%b rises=%0d", q, mirror, rises);
    #26 $display("settled q=%b mirror=%b rises=%0d", q, mirror, rises);
`ifdef LATE_WAITER
    $display("late waiter captured=%b", captured);
`endif
    $finish;
  end
endmodule
// CHECK: inactive q=0 mirror=0 rises=0
// CHECK-NEXT: settled q=1 mirror=1 rises=2
// FIFO: aot_nba_stages=0 {{.*}}nba_queue_enqueues=3{{ }}
// FIFO: talos-nba-fifo word_publications=3
// FIFO: talos-nba-fifo packed_records=3
// LATE: settled q=1 mirror=1 rises=2
// LATE-NEXT: late waiter captured=0
