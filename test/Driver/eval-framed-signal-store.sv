// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.diag
// RUN: FileCheck %s < %t.out && FileCheck %s --check-prefix=FRAME < %t.diag
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.bc && %t.bc | diff -u %t.out -

module top;
  logic left, right, left_enable, right_enable, seen_left, seen_right;
  logic [15:0] state;
  logic [3:0] source, idx;
  bit clk;
  int ticks, falling_edges;
  always #2 clk = !clk;
  always_ff @(posedge clk) ticks <= ticks + 1;
  always_comb begin
    seen_right = right;
    state[idx +: 4] = source;
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
    idx = 4;
    source = 4'bx1z0;
    #1 left_enable = 1;
    right_enable = 1;
    #5 $display("on %b%b seen %b%b", left, right, seen_left, seen_right);
    $display("state %b", state[7:4]);
    // Only bits 14 and 15 of this selection have storage (11.5.1).
    idx = 14;
    source = 4'b01zx;
    left_enable = 0;
    right_enable = 0;
    #7 $display("off %b%b seen %b%b ticks=%0d fell=%0d",
                left, right, seen_left, seen_right, ticks, falling_edges > 0);
    $display("clipped %b prior %b", state[15:14], state[7:4]);
    $finish;
  end
endmodule
// CHECK: on 11 seen 11
// CHECK-NEXT: state x1z0
// CHECK-NEXT: off 00 seen 00 ticks=3 fell=1
// CHECK-NEXT: clipped zx prior x1z0
// FRAME: talos-frame-store shared={{[1-9][0-9]*}} fallback={{[1-9][0-9]*}}
