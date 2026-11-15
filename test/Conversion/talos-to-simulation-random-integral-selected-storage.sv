// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11, 7.4: a function actual selecting storage through a
// state index lowers (no "statically selected rand
// paths" rejection) and the selected region is ordered before the call.
// CHECK: simulation.random.solve

function automatic bit flip(bit v);
  return !v;
endfunction

class A;
  rand bit y[2];
  rand bit [3:0] v;
  rand bit x, z;
  int idx = 1;
  constraint c { x == flip(y[idx]); z == flip(v[idx]); }
endclass

module top;
  A a = new;
  initial void'(a.randomize());
endmodule
