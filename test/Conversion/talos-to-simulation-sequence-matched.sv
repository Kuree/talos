// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DNOCLOCK %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=NOCLOCK

// IEEE 1800-2023 16.13.5, F.6.1: matched stores the end point of the source until
// the first tick of the destination clock after it, so each use records the end
// points and the ticks in four time words of its own.
module top;
  bit clk, slow, a, b, r;
  sequence e1(x, y); @(posedge clk) x ##1 y; endsequence
`ifdef NOCLOCK
  assert property (e1(a, b).matched);
`else
  cover property (@(posedge slow) r ##1 e1(a, b).matched);
`endif
endmodule

// NOCLOCK: the sequence method matched can only be used in a clocked sequence expression

// CHECK-COUNT-4: simulation.storage.decl {{.*}}debug "sequence method matched record"
