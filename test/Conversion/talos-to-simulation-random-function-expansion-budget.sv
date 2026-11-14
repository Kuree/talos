// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt --lower-talos-to-sim=opt-level=0 | FileCheck %s
// REQUIRES: compiled-sampler

// Constraint function calls expand into the constraint's expression tree, and
// each use of a computed local copies its expression. Fifteen iterations of
// t = (t + t) - t would copy 3^15 trees; the expansion is bounded and
// replaced by native execution instead of exhausting compile time.
class C;
  rand bit [7:0] v;
  function automatic bit [7:0] f(bit [7:0] x);
    bit [7:0] t = x;
    repeat (15) t = (t + t) - t;
    return t;
  endfunction
  // CHECK: simulation.random.function_stage
  // CHECK-SAME: SAMP
  constraint c { f(v) >= 10; }
endclass

module top;
  C c = new;
  initial void'(c.randomize());
endmodule
