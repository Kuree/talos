// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: a pure automatic function whose actuals are state
// is evaluated prev solving, as ordinary code; here every body is too long
// to expand into a relation. Pins native execution of loops, wide returns,
// recursion, const-ref inputs, guards, and unknown results (randomize fails).
// CHECK: wrapper PASS
// CHECK-NEXT: wide PASS
// CHECK-NEXT: recursion PASS
// CHECK-NEXT: constref PASS
// CHECK-NEXT: guard PASS
// CHECK-NEXT: unknown PASS

class C;
  rand bit [7:0] y;
  rand bit [129:0] w;
  rand bit [7:0] z, g, u;
  bit [7:0] n = 8'd5;
  bit en = 0;
  bit mk = 0;
  bit [7:0] hold = 8'd77;

  function automatic bit [7:0] lin(bit [7:0] v);
    bit [7:0] acc = 0;
    for (int i = 0; i < 513; i++) acc = acc + v;
    return acc;
  endfunction
  function automatic bit [7:0] outer(bit [7:0] v);
    return lin(v) + 8'd1;
  endfunction
  function automatic bit [129:0] wide(bit [7:0] v);
    bit [129:0] acc = 0;
    for (int i = 0; i < 514; i++) acc = acc + {122'd0, v} + 130'h1_0000_0000_0000_0000_0000;
    return acc;
  endfunction
  function automatic bit [7:0] rec(bit [7:0] v);
    if (v == 0) return 0;
    for (int i = 0; i < 513; i++) begin end
    return rec(v - 1) + 1;
  endfunction
  function automatic bit [7:0] cr(const ref bit [7:0] v);
    bit [7:0] acc = 0;
    for (int i = 0; i < 513; i++) acc = v;
    return acc + 8'd2;
  endfunction
  function automatic bit [7:0] maybe_x(bit [7:0] v);
    logic [7:0] r = v;
    for (int i = 0; i < 513; i++) begin end
    if (v == 8'd9) r = 8'bx;
    return r;
  endfunction

  constraint cw { y == outer(n); }
  constraint cwide { w == wide(n); }
  constraint crec { z == rec(n); }
  constraint ccr { g == cr(n); }
  constraint cgd { en -> u == lin(n); }
  constraint cx { mk -> u == maybe_x(8'd9); }
endclass

module top;
  C o = new;
  initial begin
    bit [129:0] expw;
    bit [7:0] prev;
    // 513 * 5 + 1 = 2566 = 6 mod 256.
    if (!o.randomize()) $fatal(1, "randomize failed");
    if (o.y !== 8'd6) $fatal(1, "wrapper y=%0d", o.y);
    $display("wrapper PASS");
    expw = 130'd5 * 514 + 514 * 130'h1_0000_0000_0000_0000_0000;
    if (o.w !== expw) $fatal(1, "wide w=%h", o.w);
    $display("wide PASS");
    if (o.z !== 8'd5) $fatal(1, "rec z=%0d", o.z);
    $display("recursion PASS");
    if (o.g !== 8'd7) $fatal(1, "constref g=%0d", o.g);
    $display("constref PASS");
    // The disabled guard skips lin(); enabling it follows the call result.
    o.n = 8'd3;
    if (!o.randomize()) $fatal(1, "n=3 failed");
    if (o.y !== 8'd4 || o.z !== 8'd3 || o.g !== 8'd5) $fatal(1, "n=3 results");
    o.en = 1;
    if (!o.randomize() || o.u !== 8'(513 * 3)) $fatal(1, "guard u=%0d", o.u);
    $display("guard PASS");
    // An X return leaves no valid assignment; fields are unchanged.
    o.mk = 1;
    prev = o.y;
    if (o.randomize()) $fatal(1, "unknown return accepted");
    if (o.y !== prev || o.u !== 8'(513 * 3)) $fatal(1, "fields changed");
    $display("unknown PASS");
  end
endmodule
