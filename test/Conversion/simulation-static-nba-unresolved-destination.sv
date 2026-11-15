// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3 timing=true' -o /dev/null 2> %t.trace
// RUN: FileCheck %s < %t.trace

// IEEE 1800-2023 4.6(b), 10.4.2: nonblocking updates of one variable apply in
// execution order. An NBA through a virtual interface (25.9) may write any
// instance's variable, here the same i0.s the next statement writes. The
// final CFG preparation specializes the finite reference choice on each
// incoming edge, exposing both roots while preserving the two NBAs' source
// order (i0.s ends as a + 8'h10). No unrooted commit remains to prevent static
// specialization; simulation-static-handle-tail-nba.mlir checks both paths
// and the conservative policy before that normalization.
interface ifc;
  logic [7:0] s = 0;
endinterface

module top;
  logic clk = 0;
  always #5 clk = ~clk;
  ifc i0();
  ifc i1();
  virtual ifc v;
  logic [7:0] a = 1;
  always_ff @(posedge clk) a <= a + 1;
  initial begin
    if ($test$plusargs("one")) v = i1;
    else v = i0;
  end
  always_ff @(posedge clk) begin
    v.s <= a;
    i0.s <= a + 8'h10;
  end
endmodule

// CHECK: talos native NBA batch: candidates=0 roots=2
