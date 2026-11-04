// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3 timing=true' --mlir-print-ir-after=talos-sim-specialize-static-state-nba -o /dev/null 2> %t.trace
// RUN: FileCheck %s < %t.trace
// RUN: FileCheck %s --check-prefix=IR < %t.trace

// IEEE 1800-2023 4.6(b), 10.4.2: an NBA blocks static accumulators only when
// its destination may be any root. The task below waits, then assigns r; its
// destination reaches the assignment as a block argument of the resumed
// body, yet the compute graph still resolves the commit to r alone. So both r
// and a keep their static NBA roots and run in generated code.
module top;
  logic clk = 0;
  logic [7:0] r = 0;
  logic [15:0] a = 16'h1234;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 1;
  task automatic waitdrive(input logic [7:0] v);
    @(posedge clk);
    r <= v;
  endtask
  initial repeat (3) waitdrive(a[7:0]);
  always @(negedge clk) $display("r=%h a=%h", r, a);
  initial #42 $finish;
endmodule

// CHECK: talos native unchanged NBA roots: 2/2
// CHECK: talos eval executor inventory: tier1=2 tier2=0 runtime_checkpoints=0
// CHECK: talos native NBA batch: candidates=2 roots=2

// The shape this test exists for: r's destination is a block argument of the
// resumed task body, and both roots are planned.
// IR: nbaRoots = [1, 2]
// IR: ^bb{{[0-9]+}}(%[[REF:[0-9]+]]: !simulation.ref<!simulation.packed_array<7 : 0
// IR-NEXT: simulation.nba.enqueue %arg1 to %[[REF]]
