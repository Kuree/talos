// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic --mlir-timing %s -o %t 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.clocked && %t.clocked | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.2s && %t.2s | diff -u %t.out -

module top;
  logic left, right, left_enable, right_enable, seen_left, seen_right;
  bit clk;
  int ticks, falling_edges;
  always #2 clk = !clk;
  always_ff @(posedge clk) ticks <= ticks + 1;

  // Both Active processes publish intermediate zeroes. A handoff may run
  // an armed peer between statements in source order (1800-2023 4.6–4.7).
  always_comb begin
    seen_right = right;
    left = 0;
    left = left_enable;
  end
  always_comb begin
    seen_left = left;
    right = 0;
    right = right_enable;
  end
  always @(negedge left or negedge right) falling_edges++;

  initial begin
    #1 left_enable = 1;
    right_enable = 1;
    #5 $display("on %b%b seen %b%b", left, right, seen_left, seen_right);
    left_enable = 0;
    right_enable = 0;
    #7 $display("off %b%b seen %b%b ticks=%0d fell=%0d",
                left, right, seen_left, seen_right, ticks, falling_edges > 0);
    $finish;
  end
endmodule
// PLAN: talos Active re-arm interleaving: members=2
// PLAN: talos ranked Active waits: actors=2 static-rows=4
// CHECK: on 11 seen 11
// CHECK-NEXT: off 00 seen 00 ticks=3 fell=1
