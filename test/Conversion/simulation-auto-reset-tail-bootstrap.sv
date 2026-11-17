// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto timing=true' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s < %t.mlir

// An initial procedure executes once (IEEE 1800-2023 9.2.1). A wait that no
// control-flow cycle reaches again, like the reset sequence's final negedge
// or the one-shot waits of the last initial, belongs to the finite prefix
// the runtime drains before the generated periodic loop owns the clock. It
// needs no generated executor, so the partial island keeps its eval
// coordinator.
// TRACE: talos eval runtime-calendar eligibility: island=1
// TRACE-NOT: partial eval disabled
// TRACE: talos eval executor inventory: tier1=
// TRACE-NOT: partial eval disabled
// CHECK: llvm.func @__talos_eval_dispatch_v1

module reset_tail_bootstrap;
  logic clk = 0;
  logic rst_n = 0;
  logic [7:0] cnt;
  logic [7:0] twice;
  logic hit = 0;
  int seen = 0;
  initial forever #5 clk = ~clk;
  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  end
  always @(posedge clk)
    if (!rst_n) cnt <= 0;
    else cnt <= cnt + 1;
  assign twice = cnt << 1;
  initial begin
    @(negedge clk);
    @(posedge cnt[2]);
    hit = 1;
    seen = cnt;
  end
  initial begin
    #200;
    $display("cnt=%0d twice=%0d rst_n=%b hit=%0d seen=%0d", cnt, twice, rst_n,
             hit, seen);
    $finish;
  end
endmodule
