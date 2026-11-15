// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=PLAN
// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t +ntb_random_seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5/18.5.9: the live captures count and exponent
// specialize one compiled sampling plan, embedded in the solve operation.
// PLAN: simulation.random.solve
// PLAN-SAME: SAMP
// PLAN-SAME: PLAN

// The same plan serves zero, singleton, mid-popcount, full-popcount and
// impossible states of a 65-bit variable. Crossing 64 bits suffices to force
// residual sampling without constructing a 130-bit mid-popcount diagram.
// A failed call (18.6.3) preserves the last
// assignment. Each line below is the verdict of one captured state.
// CHECK: bit 64 1
// CHECK-NEXT: popcount 32 1
// CHECK-NEXT: zero 1
// CHECK-NEXT: full 1
// CHECK-NEXT: negative count 1
// CHECK-NEXT: exponent past width 1

module top;
  bit [64:0] x = '0;
  int count = 0;
  int exponent = 0;
  int status;
  bit [64:0] kept;

  task automatic draw();
    status = std::randomize(x) with { $countones(x) == count;
                                      $clog2(x) == exponent; };
  endtask

  initial begin
    count = 1; exponent = 64; draw();
    $display("bit 64 %0d",
             status == 1 && x == 65'h10000000000000000);

    count = 32; exponent = 65; draw();
    $display("popcount 32 %0d",
             status == 1 && $countones(x) == 32 && $clog2(x) == 65);

    count = 0; exponent = 0; draw();
    $display("zero %0d", status == 1 && x == 65'h0);

    count = 65; exponent = 65; draw();
    $display("full %0d",
             status == 1 && x == 65'h1ffffffffffffffff);

    kept = x;
    count = -1; exponent = 65; draw();
    $display("negative count %0d", status == 0 && x == kept);

    count = 1; exponent = 66; draw();
    $display("exponent past width %0d", status == 0 && x == kept);
  end
endmodule
