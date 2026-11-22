// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4/18.5, 11.4.5: fixed real arrays compare element by
// element as IEEE numbers (-0.0 == 0.0, NaN != NaN). Pinned: whole-array
// ==/!= against state arrays, state-selected elements a[idx] with an invalid
// index (7.4.5), conditional operands that are whole arrays, array-returning
// functions, and failed requests leaving all fields unchanged.
// CHECK: whole comparisons PASS
// CHECK-NEXT: selected PASS
// CHECK-NEXT: conditional PASS
// CHECK-NEXT: array return PASS
// CHECK-NEXT: scope PASS

typedef real r2_t[2];

class W;
  rand real r[2];
  rand shortreal q[2];
  real s[2];
  shortreal t[2];
  int idx;
  bit eq, sel;
  rand real x;
  real m[2][2];
  constraint c {
    if (eq) { r == s; q == t; } else { r != s; q != t; }
    x == m[idx][1];
    sel ? r == s : r != s;
  }
endclass

class F;
  rand real r[2];
  real base[2];
  function r2_t twice(real v);
    r2_t o; o[0] = v; o[1] = v * 2.0; return o;
  endfunction
  real v = 1.5;
  constraint c { r == twice(v); }
endclass

module top;
  W w = new;
  F f = new;
  real a[2], b[2];
  int ok;
  initial begin
    real nan, nz;
    r2_t keep;
    nan = $bitstoreal(64'h7ff8000000000000);
    nz  = $bitstoreal(64'h8000000000000000);
    w.m[0][1] = 10.0; w.m[1][1] = 20.0;
    w.idx = 1;

    // eq: r == s elementwise; signed zero is equal to zero.
    w.eq = 1; w.sel = 1;
    w.s[0] = nz; w.s[1] = 2.5; w.t[0] = 1.0; w.t[1] = 3.0;
    ok = w.randomize();
    if (!ok) $fatal(1, "eq failed");
    if (w.r[0] != 0.0 || w.r[1] != 2.5 || w.q[1] != 3.0) $fatal(1, "eq values");
    // NaN never equals anything, so r == s cannot hold.
    w.s[0] = nan;
    keep[0] = w.r[0]; keep[1] = w.r[1];
    ok = w.randomize();
    if (ok) $fatal(1, "NaN equality accepted");
    if ($realtobits(w.r[0]) != $realtobits(keep[0]) || w.r[1] != keep[1])
      $fatal(1, "rollback");
    // ...while != holds trivially.
    w.eq = 0; w.sel = 0;
    ok = w.randomize();
    if (!ok) $fatal(1, "NaN inequality failed");
    w.s[0] = 0.0; w.s[1] = 1.0; w.t[0] = 4.0; w.t[1] = 5.0;
    repeat (4) begin
      ok = w.randomize();
      if (!ok || (w.r[0] == 0.0 && w.r[1] == 1.0)) $fatal(1, "ne violated");
    end
    $display("whole comparisons PASS");

    // x == m[idx][1] follows the selected row; an invalid index leaves the
    // constraint unsatisfiable-or-erroring and the request fails.
    w.eq = 1; w.sel = 1; w.s[0] = 1.0; w.s[1] = 2.0; w.t[0] = 1.0; w.t[1] = 2.0;
    for (int i = 0; i < 2; i++) begin
      w.idx = i;
      ok = w.randomize();
      if (!ok || w.x != w.m[i][1]) $fatal(1, "selected idx %0d", i);
    end
    w.idx = 2;
    ok = w.randomize();
    if (ok) $fatal(1, "out-of-bounds index accepted");
    w.idx = 0;
    ok = w.randomize();
    if (!ok || w.x != 10.0) $fatal(1, "recovery");
    $display("selected PASS");

    // Both conditional arms are whole arrays.
    w.sel = 1;
    ok = w.randomize();
    if (!ok || w.r[1] != 2.0) $fatal(1, "sel true arm");
    w.sel = 0; w.eq = 0;
    ok = w.randomize();
    if (!ok || (w.r[0] == 1.0 && w.r[1] == 2.0)) $fatal(1, "sel false arm");
    $display("conditional PASS");

    // Array-returning function: elements are ordered after v (18.5.9).
    repeat (3) begin
      ok = f.randomize();
      if (!ok || f.r[0] != 1.5 || f.r[1] != 3.0) $fatal(1, "array return");
    end
    f.v = 2.0;
    ok = f.randomize();
    if (!ok || f.r[0] != 2.0 || f.r[1] != 4.0) $fatal(1, "array return v");
    f.r[1].rand_mode(0);
    f.r[1] = 9.0;
    ok = f.randomize();
    if (ok) $fatal(1, "frozen result contradiction accepted");
    $display("array return PASS");

    a[0] = 1.0; a[1] = nz;
    b[0] = 5.0; b[1] = 6.0;
    ok = std::randomize(b) with { b == a; };
    if (!ok || b[0] != 1.0 || b[1] != 0.0) $fatal(1, "scope eq");
    a[0] = nan;
    ok = std::randomize(b) with { b == a; };
    if (ok) $fatal(1, "scope NaN eq accepted");
    $display("scope PASS");
  end
endmodule
