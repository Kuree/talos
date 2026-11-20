// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.diag && FileCheck %s < %t.out && FileCheck %s --check-prefix=FIFO < %t.diag
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

// Each pulse wakes an armed process once. X -> Z is a change, and the
// positive edges on 0 -> X and Z -> 1 both count (1800-2023 Table 9-2).
module top;
  logic q = 0;
  int rises, changes;
  always @(posedge q) rises++;
  always @(q) changes++;

  initial begin
    #1;
    q <= 1;
    repeat (4) q <= 0;
    #1 $display("%0d %0d %b", rises, changes, q);
    repeat (3) q <= 1'bx;
    #1 $display("%0d %0d %b", rises, changes, q);
    repeat (3) q <= 1'bz;
    #1 $display("%0d %0d %b", rises, changes, q);
    repeat (2) q <= 1;
    #1 $display("%0d %0d %b", rises, changes, q);
    $finish;
  end
endmodule
// CHECK: 1 1 0
// CHECK-NEXT: 2 2 x
// CHECK-NEXT: 2 3 z
// CHECK-NEXT: 3 4 1
// FIFO: aot_nba_stages=0 {{.*}}nba_queue_enqueues=13{{ }}
