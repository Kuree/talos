// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DREADS_RANDOM -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=RANDOM

// IEEE 1800-2023 18.5.7.2: a reduction over a container that the randomize call
// does not write is state, whose value and with clause are evaluated once before
// solving. The iterator and item.index exist only while lowering the whole call.
class C;
  int s[];
  rand int z;
`ifdef READS_RANDOM
  // RANDOM: error: array reduction over a container this randomize call does not write cannot read a random variable in its with clause yet
  constraint c { (s.sum() with (item + z)) == 6; }
`else
  constraint c { z == s.sum() with (item.index * item); }
`endif
endclass
module top;
  C c = new;
  initial void'(c.randomize());
endmodule

// The whole call is lowered ahead of the solve, in one iteration over `s`.
// CHECK: simulation.container.size
// CHECK: simulation.container.read
// CHECK: arith.muli
// CHECK: simulation.random.solve
