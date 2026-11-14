// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.8/18.8: a field is random if ANY live handle reaches it,
// even when constraints name it through a frozen alias; rand_mode(0) on every
// handle or on the field freezes it; null handles are skipped; a failed
// randomize() leaves all values unchanged.
// CHECK: alias modes any-live PASS
// CHECK-NEXT: alias modes all-frozen PASS
// CHECK-NEXT: alias modes field-frozen PASS
// CHECK-NEXT: alias modes null PASS
// CHECK-NEXT: alias modes atomic PASS

class Leaf;
  rand bit x;
  rand logic [129:0] w;   // starts as all-X; random draws must be two-state
  constraint dom { w inside {0, 7}; }
endclass

class Owner;
  rand Leaf a;
  rand Leaf b;
  rand Leaf c;
  // Hard constraints through every handle describe the same actual fields.
  constraint same { a.x == b.x; b.x == c.x; a.w == c.w; }
endclass

class Pair;
  rand Leaf a;
  rand Leaf b;
  rand Leaf c;
  constraint same { a.x == b.x; }
endclass

module t;
  Owner o;
  Pair p;
  Leaf l;
  bit [1:0] sx;
  bit [1:0] sw;
  logic [129:0] w0;

  task automatic sample(string what);
    sx = 0; sw = 0;
    repeat (32) begin
      if (!o.randomize()) $fatal(1, "%s: randomize failed", what);
      if ($isunknown(l.w) || !(l.w == 0 || l.w == 7)) $fatal(1, "%s: bad w", what);
      sx[l.x] = 1; sw[l.w == 7] = 1;
    end
  endtask

  initial begin
    o = new; l = new;
    o.a = l; o.b = l; o.c = l;

    // Only one handle live (first, middle, last): the shared fields still vary.
    o.a.rand_mode(0); o.b.rand_mode(0);
    sample("last-live");
    if (sx != 2'b11 || sw != 2'b11) $fatal(1, "last-live domain");
    o.c.rand_mode(0); o.b.rand_mode(1);
    sample("middle-live");
    if (sx != 2'b11 || sw != 2'b11) $fatal(1, "middle-live domain");
    o.b.rand_mode(0); o.a.rand_mode(1);
    sample("first-live");
    if (sx != 2'b11 || sw != 2'b11) $fatal(1, "first-live domain");
    $display("alias modes any-live PASS");

    // Every handle frozen: nothing is random, values survive.
    o.a.rand_mode(0);
    l.x = 1; l.w = 130'h7; w0 = l.w;
    repeat (8) begin
      if (!o.randomize()) $fatal(1, "frozen randomize failed");
      if (l.x !== 1 || l.w !== w0) $fatal(1, "frozen value changed");
    end
    $display("alias modes all-frozen PASS");

    // All handles live but the field x frozen: only w varies.
    o.a.rand_mode(1); o.b.rand_mode(1); o.c.rand_mode(1);
    l.x.rand_mode(0); l.x = 1;
    sample("x-frozen");
    if (sx != 2'b10 || sw != 2'b11) $fatal(1, "x-frozen domain");
    l.x.rand_mode(1);
    $display("alias modes field-frozen PASS");

    // A null handle is skipped; a live alias still randomizes the shared object.
    p = new;
    p.a = l; p.b = l; p.c = null;
    p.a.rand_mode(0);
    sx = 0;
    repeat (32) begin
      if (!p.randomize()) $fatal(1, "null: randomize failed");
      sx[l.x] = 1;
    end
    if (sx != 2'b11 || p.c != null) $fatal(1, "null domain/handle");
    $display("alias modes null PASS");

    // Impossible inline constraint through two aliases: atomic failure.
    o.a.rand_mode(1); o.b = l;
    l.x = 1; l.w = 130'h7; w0 = l.w;
    if (o.randomize() with { a.x != b.x; }) $fatal(1, "impossible constraint solved");
    if (l.x !== 1 || l.w !== w0) $fatal(1, "failed randomize modified state");
    $display("alias modes atomic PASS");
  end
endmodule
