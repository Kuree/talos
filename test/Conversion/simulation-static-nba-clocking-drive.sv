// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3 timing=true' -o /dev/null 2> %t.trace
// RUN: FileCheck %s < %t.trace

// IEEE 1800-2023 14.16: a clocking-block drive updates its signal in the
// Re-NBA region, after the NBA region where static NBA accumulators commit.
// Its commit names no single storage root (the drive's target is an argument
// of the clocking output process), so the static NBA plan leaves it on the
// generic frontier as an ordered boundary without a root, instead of
// rejecting the design ("static NBA commit does not identify one fixed storage
// root"). The registers keep their static roots and run in generated code,
// also the first declared one, whose descriptor the unrooted commit's
// placeholder matches.
module top;
  logic [7:0] q = 8'h05;
  logic clk = 0;
  logic [7:0] d;
  logic [15:0] a = 16'h1234;
  always #5 clk = ~clk;
  always_ff @(posedge clk) begin a <= a + 1; q <= q + 1; end
  clocking cb @(posedge clk);
    output d;
  endclocking
  initial begin
    repeat (3) begin
      @(cb);
      cb.d <= a[7:0];
    end
  end
endmodule

// CHECK: talos native unchanged NBA roots: 2/2
// CHECK: ordered NBA boundary: function={{.*}}$clocking_output{{[^ ]*}} site={{[0-9]+}} root=4294967295
// CHECK: talos eval executor inventory: tier1=1 tier2=0 runtime_checkpoints=0
// CHECK: talos native NBA batch: candidates=2 roots=2
