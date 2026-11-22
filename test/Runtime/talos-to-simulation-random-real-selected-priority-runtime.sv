// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.9/18.5.11: a rand argument of a constraint function is
// solved before the call result. With a real array actual a[idx] and a state
// index, only the selected leaf is ordered ahead of the function, so the
// result constraint rejects about half of the draws; a frozen selected leaf
// decides the outcome, and an invalid index (7.4.5) is an error.
// CHECK: ordered leaf PASS
// CHECK-NEXT: frozen leaves PASS
// CHECK-NEXT: invalid index PASS
// CHECK-NEXT: shortreal 2-D PASS

class C;
  rand real a[2];
  rand real y;
  int idx;
  function real sign(real v);
    return v > 0.0 ? 1.0 : -1.0;
  endfunction
  constraint c { y > 0.0; y == sign(a[idx]); }
endclass

class D;
  rand shortreal m[2][2];
  rand shortreal y;
  int row, col;
  function shortreal sign(shortreal v);
    return v > 0.0 ? 1.0 : -1.0;
  endfunction
  constraint c { y > 0.0; y == sign(m[row][col]); }
endclass

module top;
  C c = new;
  D d = new;
  int ok, fails, k;
  initial begin
    // Selected leaf is solved first: it is positive only about half the time.
    for (int i = 0; i < 2; i++) begin
      c.idx = i;
      fails = 0;
      repeat (64) begin
        c.srandom(k++); ok = c.randomize();
        if (ok) begin
          if (c.a[i] <= 0.0 || c.y != 1.0) $fatal(1, "bad success");
        end else fails++;
      end
      if (fails < 16 || fails > 48) $fatal(1, "idx %0d fails %0d", i, fails);
    end
    $display("ordered leaf PASS");

    // The unselected leaf is irrelevant: freeze it negative, nothing changes
    // for idx 0; freeze the selected leaf and the outcome is decided by it.
    c.a[1] = -1.0; c.a[1].rand_mode(0);
    c.idx = 0;
    ok = 0; repeat (16) begin c.srandom(k++); ok += c.randomize(); end
    if (ok == 0 || ok == 16) $fatal(1, "unselected frozen leaf mattered");
    if (c.a[1] != -1.0) $fatal(1, "frozen changed");
    c.idx = 1;
    repeat (8) if (c.randomize()) $fatal(1, "negative frozen leaf accepted");
    c.a[1] = 2.0;
    repeat (8) if (!c.randomize()) $fatal(1, "positive frozen leaf rejected");
    $display("frozen leaves PASS");

    c.idx = 2;
    if (c.randomize()) $fatal(1, "idx 2 accepted");
    c.idx = -1;
    if (c.randomize()) $fatal(1, "idx -1 accepted");
    c.idx = 0;
    c.a[1].rand_mode(1);
    ok = 0; repeat (16) begin c.srandom(k++); ok += c.randomize(); end
    if (ok == 0) $fatal(1, "recovery");
    $display("invalid index PASS");

    d.row = 1; d.col = 0;
    fails = 0;
    repeat (64) begin
      d.srandom(k++); ok = d.randomize();
      if (ok) begin
        if (d.m[1][0] <= 0.0) $fatal(1, "bad shortreal success");
      end else fails++;
    end
    if (fails < 16 || fails > 48) $fatal(1, "2-D fails %0d", fails);
    d.row = 0; d.col = 3;
    if (d.randomize()) $fatal(1, "2-D OOB accepted");
    $display("shortreal 2-D PASS");
  end
endmodule
