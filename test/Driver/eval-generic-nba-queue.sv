// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t 2> %t.diag | FileCheck %s
// RUN: FileCheck %s --check-prefix=QUEUE < %t.diag
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.clocked
// RUN: %t.clocked | FileCheck %s
//
// Both NBAs capture their RHS in Active and run in enqueue order at the NBA
// barrier. Each 0 -> 1 -> 0 pulse still wakes the edge observer (4.6(b), 9.4.2).
module top;
  bit clk, start = 1;
  logic [72:0] q = 0;
  int rises = 0, samples = 0;
  logic [2:0] narrow = 0;
  int narrow_rises = 0;
  bit mixed = 0;
  always #5 clk = !clk;
  always @(posedge clk) begin
    if (start) begin
      q <= 73'h100000000000000001;
      q <= 73'h0;
      narrow <= 3'b11x;
      narrow <= 0;
    end
    // Equality at capture is insufficient when a blocking writer intervenes.
    mixed <= mixed;
    mixed = !mixed;
    samples <= samples + 1;
  end
  always @(posedge q[0]) rises++;
  always @(posedge narrow[0]) narrow_rises++;
  initial begin
    #20 start = 0;
    #12 $display("rises=%0d samples=%0d q=%h mixed=%b", rises, samples, q, mixed);
    $display("narrow=%b narrow_rises=%0d", narrow, narrow_rises);
    $finish;
  end
endmodule
// CHECK: rises=2 samples=3 q=0000000000000000000 mixed=0
// CHECK-NEXT: narrow=000 narrow_rises=2
// The four changes of knownness take full four-state commit at their own
// queue positions. The later records in the same barriers resume packed replay.
// QUEUE: nba_queue_enqueues=14{{ }}
// QUEUE: talos-nba-fifo packed_records=10
