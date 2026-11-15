// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.9/18.5.11/18.8: a state-selected row m[row] of a 2-D
// real array can be a const-ref function actual or an array-valued function
// target. The whole selected row is ordered before/after the call, its
// partially frozen elements decide the result, other rows are irrelevant,
// frozen NaN/Inf/-0.0 payloads are kept, and invalid rows are errors (7.4.6).
// CHECK: row actual PASS
// CHECK-NEXT: frozen rows PASS
// CHECK-NEXT: row target PASS
// CHECK-NEXT: invalid row PASS

typedef real row_t[2];

class A;
  rand real m[2][2];
  rand real y;
  int row;
  function real both_pos(const ref real r[2]);
    return (r[0] > 0.0 && r[1] > 0.0) ? 1.0 : -1.0;
  endfunction
  constraint c { y > 0.0; y == both_pos(m[row]); }
endclass

class T;
  rand real m[2][2];
  real v = 2.5;
  int row;
  function row_t mk(real x);
    row_t o; o[0] = x; o[1] = -x; return o;
  endfunction
  constraint c { m[row] == mk(v); }
endclass

module top;
  A a = new;
  T t = new;
  int ok, good, k;
  initial begin
    // Selected row solved first; roughly a quarter of rows are positive.
    for (int r = 0; r < 2; r++) begin
      a.row = r; good = 0;
      repeat (32) begin
        a.srandom(k++);
        if (a.randomize()) begin
          good++;
          if (!(a.m[r][0] > 0.0 && a.m[r][1] > 0.0)) $fatal(1, "bad row");
        end
      end
      if (good == 0 || good == 32) $fatal(1, "row %0d good %0d", r, good);
    end
    $display("row actual PASS");

    // Freezing one element of row 1 decides row 1 only.
    a.m[1][1] = -1.0; a.m[1][1].rand_mode(0);
    a.row = 1; good = 0;
    repeat (16) begin a.srandom(k++); good += a.randomize(); end
    if (good != 0) $fatal(1, "negative frozen element accepted");
    if (a.m[1][1] != -1.0) $fatal(1, "frozen element changed");
    a.row = 0; good = 0;
    repeat (32) begin a.srandom(k++); good += a.randomize(); end
    if (good == 0) $fatal(1, "unselected frozen row mattered");
    if ($realtobits(a.m[1][1]) != $realtobits(-1.0)) $fatal(1, "frozen changed");
    a.m[1][1] = $bitstoreal(64'h7ff8000000000001);
    a.row = 0; good = 0;
    repeat (32) begin a.srandom(k++); good += a.randomize(); end
    if (good == 0 || $realtobits(a.m[1][1]) != 64'h7ff8000000000001)
      $fatal(1, "NaN payload lost");
    $display("frozen rows PASS");

    // Array-valued function as target of the selected row.
    for (int r = 0; r < 2; r++) begin
      t.row = r;
      ok = t.randomize();
      if (!ok || t.m[r][0] != 2.5 || t.m[r][1] != -2.5) $fatal(1, "target %0d", r);
    end
    t.v = 4.0; t.row = 1;
    t.m[1][1].rand_mode(0); t.m[1][1] = 1.0;
    ok = t.randomize();
    if (ok) $fatal(1, "frozen target member accepted");
    t.m[1][1].rand_mode(1);
    ok = t.randomize();
    if (!ok || t.m[1][0] != 4.0 || t.m[1][1] != -4.0) $fatal(1, "target recovery");
    $display("row target PASS");

    a.row = 2;
    if (a.randomize()) $fatal(1, "row 2 accepted");
    t.row = -1;
    if (t.randomize()) $fatal(1, "row -1 accepted");
    t.row = 0;
    if (!t.randomize()) $fatal(1, "invalid recovery");
    $display("invalid row PASS");
  end
endmodule
