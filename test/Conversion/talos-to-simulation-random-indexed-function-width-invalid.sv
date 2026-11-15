// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=OK
// RUN: %talos --std=1800-2023 -emit-talos %s | talos-opt '--test-talos-edit-attributes=op=talos.sv.expression.integer_literal match={constant_value = "2"} set={constant_value = "3"}' | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=BAD
// REQUIRES: compiled-sampler

// IEEE 1800-2023 11.5.1, 18.5.11: the window "v[i +: 2]" passed to a
// constraint function selects two bits. If its width operand disagrees with the
// selected type (mutated to 3 here), reject it before forming ordering contexts.
// OK: simulation.random.solve
// BAD: error: constraint function ordering indexed selection width is inconsistent

function automatic bit lo_clear(bit [1:0] w);
  return !w[0];
endfunction

class A;
  rand bit [7:0] v;
  rand bit x;
  int i = 3;
  constraint c { x == lo_clear(v[i +: 2]); }
endclass

module top;
  A a = new;
  initial void'(a.randomize());
endmodule
