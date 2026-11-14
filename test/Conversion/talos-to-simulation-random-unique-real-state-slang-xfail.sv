// XFAIL: *
// RUN: %talos --std=1800-2023 -emit-talos %s -o %t.mlir

// IEEE 1800-2023 18.5.4 permits a singular state real variable in a unique
// group. Pinned Slang v11.0 rejects the state operand. Keep this frontend
// limitation explicit; the companion MLIR runtime test exercises Talos
// semantics without changing Slang.
class C;
  rand real value;
  real excluded;
  constraint distinct { unique {value, excluded}; }
endclass

module top;
  C c = new;
  initial void'(c.randomize());
endmodule
