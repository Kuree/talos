// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11/18.5.12: native constraint calls nested under shared
// guards keep guard polarity, rand_mode and rollback semantics (siblings,
// calls inside predicates, nested actuals, frozen targets, recovery).
// CHECK: nested guard prefixes PASS
// CHECK-NEXT: guard polarity PASS
// CHECK-NEXT: disabled outer guard PASS
// CHECK-NEXT: frozen mode rollback PASS
// CHECK-NEXT: recovery PASS

class C;
  rand bit [7:0] a, b, r1, r2, r3;
  bit g0 = 1, g1 = 1, g2 = 1;

  // The loop keeps the body native instead of expanding it into the solver.
  function automatic bit [7:0] f(bit [7:0] v);
    bit [7:0] t = v;
    for (int i = 0; i < 40; i++) t = t + 8'(i);
    return t;
  endfunction

  constraint c {
    if (g0) {
      r1 == f(a);                     // outer prefix shared by siblings
      if (g1) {
        r2 == f(b);
        if (g2) { r3 == f(a + b); }   // native call nested in a native actual's guard
      }
      if (!g1) { r2 == f(a); }        // inverse polarity branch
    }
    if (f(a) < 8'd128) { b < 8'd10; }   // native call in a predicate
  }
endclass

module top;
  C o = new;
  int bad;
  bit [7:0] frozen;
  function automatic bit [7:0] ref_f(bit [7:0] v);
    bit [7:0] t = v;
    for (int i = 0; i < 40; i++) t = t + 8'(i);
    return t;
  endfunction
  initial begin
    // all guards on
    repeat (20) begin
      if (!o.randomize()) $fatal(1, "all guards randomize failed");
      if (o.r1 != ref_f(o.a) || o.r2 != ref_f(o.b) || o.r3 != ref_f(8'(o.a + o.b)))
        $fatal(1, "nested guards violated");
    end
    $display("nested guard prefixes PASS");
    // inner guard off: inverse polarity branch applies, r3 is free
    o.g1 = 0;
    repeat (20) begin
      if (!o.randomize()) $fatal(1, "g1 off randomize failed");
      if (o.r1 != ref_f(o.a) || o.r2 != ref_f(o.a)) $fatal(1, "polarity violated");
    end
    $display("guard polarity PASS");
    // outer guard off: no call constraints hold, results must vary freely
    o.g0 = 0;
    bad = 0;
    repeat (40) begin
      if (!o.randomize()) $fatal(1, "g0 off randomize failed");
      if (o.r1 == ref_f(o.a)) bad++;
    end
    if (bad > 10) $fatal(1, "disabled guard still constrains (%0d)", bad);
    $display("disabled outer guard PASS");
    // r1 frozen with its guard on: the argument is solved first (18.5.9), so the
    // constraint mostly fails; every failure must roll back completely
    o.g0 = 1; o.g1 = 1;
    o.r1.rand_mode(0);
    o.r1 = ref_f(8'd5) + 8'd1;
    begin
      frozen = o.r1;
      bad = 0;
      repeat (40) begin
        if (o.randomize()) begin
          if (o.r1 != frozen || o.r1 != ref_f(o.a)) $fatal(1, "frozen constraint violated");
        end else begin
          if (o.r1 != frozen) $fatal(1, "failure changed frozen field");
          bad++;
        end
      end
      if (bad < 20) $fatal(1, "frozen failures too few: %0d", bad);
    end
    $display("frozen mode rollback PASS");
    o.r1.rand_mode(1);
    if (!o.randomize()) $fatal(1, "recovery failed");
    $display("recovery PASS");
  end
endmodule
