// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.8/18.5.13: two rand handles to one object randomize one
// set of variables. The native candidate checker must enforce the same alias
// equalities as the solver, or the second handle's unchecked slice is written
// back over the constrained one.
// CHECK: alias checker hard PASS
// CHECK-NEXT: alias checker soft PASS

class Leaf;
  rand bit [1:0] x;
  rand bit y;
endclass

class Hard;
  rand Leaf a, b;
  constraint k { a.x == 2; }
endclass

class SoftLeaf;
  rand bit [1:0] x;
  rand bit y;
  constraint prefs { soft x[0] == 1; soft x[1] == 1; soft y == 1; }
endclass

// The later soft outranks the contained preferences (18.5.13.1) after the
// disable soft discards their x[0] preference (18.5.13.2).
class Soft;
  rand SoftLeaf a, b;
  constraint drop { disable soft a.x[0]; }
  constraint later { soft a.x[0] == 0; }
endclass

module top;
  initial begin
    static Hard h = new;
    static Leaf shared = new;
    static Soft s = new;
    static SoftLeaf leaf = new;
    h.a = shared;
    h.b = shared;
    repeat (64) begin
      if (!h.randomize()) $fatal(1, "hard alias randomize failed");
      if (shared.x != 2) $fatal(1, "hard constraint lost through alias: %0d", shared.x);
    end
    $display("alias checker hard PASS");
    s.a = leaf;
    s.b = leaf;
    repeat (64) begin
      if (!s.randomize()) $fatal(1, "soft alias randomize failed");
      if (leaf.x != 2'b10 || leaf.y != 1)
        $fatal(1, "soft priorities lost through alias: x=%b y=%b", leaf.x, leaf.y);
    end
    $display("alias checker soft PASS");
  end
endmodule
