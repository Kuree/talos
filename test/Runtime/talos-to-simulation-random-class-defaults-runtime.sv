// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 8.7/6.8 (Table 6-7): uninitialized class 4-state fields
// (scalar, packed, nested struct, fixed array with negative range) start as X,
// 2-state ones as 0, real as 0.0, string empty, handle null. Own defaults are
// applied after super.new() and before the rest of the derived constructor,
// so writes made by a virtual method called from the base constructor are
// reset, explicit initializers survive, and static fields are not reset.
// CHECK: class defaults typed PASS
// CHECK-NEXT: class defaults ctor order PASS
// CHECK-NEXT: class defaults implicit super PASS
// CHECK-NEXT: class defaults random prestate PASS

typedef struct {
  logic [1:0] p;
  bit q;
} pair_t;

class Base;
  function new();
    init();
  endfunction
  virtual function void init();
  endfunction
endclass

class Der extends Base;
  static int count = 3;
  logic l;
  logic [3:0] v;
  bit [3:0] b;
  pair_t s;
  logic [1:0] arr [-2:-1];
  real r;
  string str;
  Base h;
  int e = 7;
  int f = e + 1;
  int seen_in_body;

  virtual function void init();
    // Runs from Base::new, before Der's property defaults.
    l = 1'b0; v = 4'd5; b = 4'd5; r = 2.5; str = "dirty"; e = 99; f = 99;
    count++;
  endfunction

  function new();
    super.new();
    seen_in_body = int'($isunknown(l)) + int'(b == 0);   // sees defaults
  endfunction
endclass

class Derived2 extends Base;   // implicit super.new()
  logic [7:0] v;
  bit [7:0] b;
  int g = 5;
  virtual function void init();
    v = 8'h12; b = 8'h12; g = 1;
  endfunction
endclass

class Rnd;
  rand logic [3:0] fx;       // frozen below: keeps its default X
  rand logic [3:0] free;
  constraint c { free == 4'd9; }
endclass

module t;
  initial begin
    Der d = new;
    Der d2 = new;
    Derived2 e = new;
    Rnd r = new;

    if (!$isunknown(d.l) || !$isunknown(d.v) || !$isunknown(d.s.p) ||
        !$isunknown(d.arr[-2]) || !$isunknown(d.arr[-1]))
      $fatal(1, "4-state default not X");
    if (d.b !== 0 || d.s.q !== 0 || d.r != 0.0 || d.str != "" || d.h != null)
      $fatal(1, "2-state/real/string/handle default wrong");
    $display("class defaults typed PASS");

    if (d.e != 7 || d.f != 8) $fatal(1, "explicit initializers: %0d %0d", d.e, d.f);
    if (d.seen_in_body != 2) $fatal(1, "body ran before defaults");
    if (Der::count != 5) $fatal(1, "static reset/shared: %0d", Der::count);
    $display("class defaults ctor order PASS");

    if (!$isunknown(e.v) || e.b !== 0 || e.g != 5) $fatal(1, "implicit super defaults");
    $display("class defaults implicit super PASS");

    r.fx.rand_mode(0);
    if (!r.randomize()) $fatal(1, "randomize failed");
    if (!$isunknown(r.fx) || r.free !== 9) $fatal(1, "frozen X / constrained value");
    r.fx = 4'bz1z0;
    void'(r.randomize());
    if (r.fx !== 4'bz1z0) $fatal(1, "frozen Z changed");
    $display("class defaults random prestate PASS");
  end
endmodule
