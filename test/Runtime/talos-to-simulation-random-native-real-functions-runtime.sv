// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4.1/18.5.11: pure real, shortreal and realtime functions
// run natively on accepted arguments (bodies too long to expand). Pins the
// real result relation, IEEE rounding of shortreal locals, recursive realtime
// returns, and failure (NaN result) leaving fields unchanged.
// CHECK: real stage PASS
// CHECK-NEXT: shortreal PASS
// CHECK-NEXT: recursion PASS
// CHECK-NEXT: nonfinite PASS

class C;
  rand bit [3:0] a;
  rand real r;
  rand shortreal sr;
  rand bit [7:0] t;
  real bad = 1.0e200;
  bit use_bad = 0;

  function automatic real twice(real v);
    real acc = 0.0;
    for (int i = 0; i < 513; i++) acc = v + v;
    return acc;
  endfunction
  function automatic shortreal rnd(real v);
    shortreal s = 0.0;
    for (int i = 0; i < 513; i++) s = v;
    return s;
  endfunction
  function automatic realtime down(realtime v);
    if (v <= 0.0) return 0.0;
    for (int i = 0; i < 513; i++) begin end
    return down(v - 1.0) + 1.0;
  endfunction
  function automatic real nan(real v, real d);
    real acc = 0.0;
    for (int i = 0; i < 513; i++) begin acc = v * v; acc = acc - acc; end
    return acc;
  endfunction

  constraint ca { a < 8; }
  constraint cr { r == twice(real'(a)); }
  constraint cs { sr == rnd(1.0 + 1.0 / 16777216.0); }
  constraint ct { t == int'(down(real'(a))); }
  constraint cn { use_bad -> r == nan(bad, bad); }
endclass

module top;
  C o = new;
  initial begin
    real expect_sr;
    bit [3:0] pa;
    real pr;
    repeat (10) begin
      if (!o.randomize()) $fatal(1, "randomize failed");
      if (o.r != 2.0 * real'(o.a)) $fatal(1, "real r=%f a=%0d", o.r, o.a);
    end
    $display("real stage PASS");
    // 1 + 2^-24 is not representable in shortreal: it rounds to 1.0.
    if (o.sr != 1.0) $fatal(1, "shortreal sr=%f", o.sr);
    $display("shortreal PASS");
    if (o.t !== 8'(o.a)) $fatal(1, "recursion t=%0d a=%0d", o.t, o.a);
    $display("recursion PASS");
    pa = o.a; pr = o.r;
    o.use_bad = 1;
    if (o.randomize()) $fatal(1, "NaN result accepted");
    if (o.a !== pa || o.r != pr) $fatal(1, "failure changed fields");
    $display("nonfinite PASS");
  end
endmodule
