// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.13.1/18.5.13.2: `disable soft` discards earlier soft
// constraints on the same object field reached through ANY handle to that
// object. Pins alias matching, distinct objects, higher-priority softs, and
// packed-bit disjointness.
// CHECK: alias disable aliased PASS
// CHECK-NEXT: alias disable distinct PASS
// CHECK-NEXT: alias disable priority PASS
// CHECK-NEXT: alias disable null PASS

class Leaf;
  rand bit [1:0] x;
  constraint prefs { soft x[0] == 1; soft x[1] == 1; }
endclass

class Owner;
  rand Leaf a;
  rand Leaf b;
  bit late;
  constraint drop { disable soft a.x[0]; }
  constraint later { if (late) soft b.x[0] == 0; }
endclass

module t;
  initial begin
    static Owner o = new;
    static Leaf l1 = new, l2 = new;
    bit [3:0] seen;

    // a and b alias one object: x[0] preference is gone for both paths.
    o.a = l1; o.b = l1;
    seen = 0;
    repeat (64) begin
      if (!o.randomize()) $fatal(1, "aliased randomize failed");
      if (l1.x[1] !== 1'b1) $fatal(1, "disjoint soft lost");
      seen[l1.x] = 1;
    end
    if (seen != 4'b1100) $fatal(1, "alias: x[0] not freed, seen=%b", seen);
    $display("alias disable aliased PASS");

    // b is a distinct object: its x[0] preference still holds.
    o.b = l2;
    seen = 0;
    repeat (64) begin
      if (!o.randomize()) $fatal(1, "distinct randomize failed");
      if (l2.x !== 2'b11) $fatal(1, "distinct object lost softs");
      seen[l1.x] = 1;
    end
    if (seen != 4'b1100) $fatal(1, "distinct: a side not freed");
    $display("alias disable distinct PASS");

    // A later soft keeps priority over the earlier disable, via either alias.
    o.b = l1; o.late = 1;
    repeat (16) begin
      if (!o.randomize()) $fatal(1, "priority randomize failed");
      if (l1.x !== 2'b10) $fatal(1, "later soft ignored: %b", l1.x);
    end
    $display("alias disable priority PASS");

    // A null alias is not matched and not dereferenced.
    o.late = 0; o.b = null;
    seen = 0;
    repeat (64) begin
      if (!o.randomize()) $fatal(1, "null randomize failed");
      if (l1.x[1] !== 1'b1) $fatal(1, "disjoint soft lost with null b");
      seen[l1.x] = 1;
    end
    if (seen != 4'b1100 || o.b != null) $fatal(1, "null b: seen=%b", seen);
    $display("alias disable null PASS");
  end
endmodule
