// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt '--lower-talos-to-sim=opt-level=0' --print-op-stats -o /dev/null 2>&1 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: 16 native calls under 40 nested guards must share
// guard-prefix computation. Guard AND count stays linear in depth (about 62
// here; per-call rebuilding of every enclosing predicate would be ~depth x
// calls = 600+). Only the op count is pinned; nothing is executed.
// CHECK: arith.andi{{ *}}, {{([0-9]|[1-9][0-9]|100) *$}}

class P;
  rand bit [7:0] r [16];
  rand bit [7:0] a;
  bit [39:0] g;
  function automatic bit [7:0] f(bit [7:0] v);
    bit [7:0] t = v;
    for (int i = 0; i < 40; i++) t = t + 8'(i) * v;
    return t;
  endfunction
  constraint c {
    if (g[0]) {
    if (g[1]) {
    if (g[2]) {
    if (g[3]) {
    if (g[4]) {
    if (g[5]) {
    if (g[6]) {
    if (g[7]) {
    if (g[8]) {
    if (g[9]) {
    if (g[10]) {
    if (g[11]) {
    if (g[12]) {
    if (g[13]) {
    if (g[14]) {
    if (g[15]) {
    if (g[16]) {
    if (g[17]) {
    if (g[18]) {
    if (g[19]) {
    if (g[20]) {
    if (g[21]) {
    if (g[22]) {
    if (g[23]) {
    if (g[24]) {
      r[0] == f(a + 8'd0);
    if (g[25]) {
      r[1] == f(a + 8'd1);
    if (g[26]) {
      r[2] == f(a + 8'd2);
    if (g[27]) {
      r[3] == f(a + 8'd3);
    if (g[28]) {
      r[4] == f(a + 8'd4);
    if (g[29]) {
      r[5] == f(a + 8'd5);
    if (g[30]) {
      r[6] == f(a + 8'd6);
    if (g[31]) {
      r[7] == f(a + 8'd7);
    if (g[32]) {
      r[8] == f(a + 8'd8);
    if (g[33]) {
      r[9] == f(a + 8'd9);
    if (g[34]) {
      r[10] == f(a + 8'd10);
    if (g[35]) {
      r[11] == f(a + 8'd11);
    if (g[36]) {
      r[12] == f(a + 8'd12);
    if (g[37]) {
      r[13] == f(a + 8'd13);
    if (g[38]) {
      r[14] == f(a + 8'd14);
    if (g[39]) {
      r[15] == f(a + 8'd15);
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
  }
endclass
module top; P o = new; initial void'(o.randomize()); endmodule
