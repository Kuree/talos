// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.diag && FileCheck %s < %t.out && FileCheck %s --check-prefix=FIFO < %t.diag
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

module top;
  typedef logic [511:0] lanes_t [2];
  lanes_t q, zeros = '{default:'0}, pulse = '{512'd1, 512'd0};
  lanes_t unknown_bit = '{512'd0, {511'd0, 1'bx}};
  int rises;
  always @(posedge q[0][0]) rises++;
  initial begin
    q <= zeros;
    #1;
    q <= zeros;
    q <= pulse;
    q <= zeros;
    #1 $display("before %0d %b", rises, q[1][0]);
    q <= unknown_bit;
    #1 $display("after %0d %b", rises, q[1][0]);
    $finish;
  end
endmodule
// CHECK: before 1 0
// CHECK-NEXT: after 1 x
// FIFO: aot_nba_stages=0 {{.*}}nba_queue_enqueues=4{{ }}
