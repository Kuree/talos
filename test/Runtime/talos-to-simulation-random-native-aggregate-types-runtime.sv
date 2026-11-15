// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: pure automatic functions taking and returning
// numeric structs, packed unions and fixed arrays run natively after their
// random arguments are sampled. Writes to input copies leave the source
// untouched; each constrained result must match the procedural definition.
// A qualified rand structure actual (18.4) combines its accepted rand leaf
// with the pre-solve value of its state member.
// CHECK: native aggregate functions PASS
// CHECK-NEXT: qualified structure actual PASS

typedef struct { bit [7:0] lo; bit [7:0] hi; } pair_t;
typedef union packed { bit [15:0] w; bit [1:0][7:0] b; } u_t;
typedef bit [7:0] arr_t [3];
typedef struct { rand bit [7:0] lo; bit [7:0] hi; } qpair_t;

class C;
  rand bit [7:0] a, b, c, d;
  rand pair_t p;
  rand bit [7:0] arr0, arr1;
  rand bit [7:0] r_sum, r_u, r_arr, r_q;
  pair_t q;
  const pair_t k = '{lo: 8'd3, hi: 8'd4};

  function automatic bit [7:0] sum(pair_t x);
    pair_t y = x;
    y.lo = y.lo + 8'd1;          // write to local copy only
    for (int i = 0; i < 4; i++) y.hi = y.hi + 8'd0;
    return y.lo + y.hi;
  endfunction

  function automatic pair_t swap(pair_t x);
    pair_t y;
    y.lo = x.hi; y.hi = x.lo;
    return y;
  endfunction

  function automatic bit [7:0] usum(u_t x);
    return x.b[0] ^ x.b[1];
  endfunction

  function automatic bit [7:0] asum(arr_t x);
    arr_t y = x;
    y[2] = y[0] + y[1];
    return y[2];
  endfunction

  constraint cs {
    r_sum == sum(p);
    r_q == swap(p).lo;
    r_u == usum(u_t'({a, b}));
    r_arr == asum('{arr0, arr1, c});
  }
endclass

class Q;
  rand qpair_t s;
  rand bit [7:0] r;
  function automatic bit [7:0] diff(qpair_t x);
    return x.lo - x.hi;
  endfunction
  constraint cs { s.lo < 8'd100; r == diff(s); }
endclass

module top;
  C o = new;
  Q q = new;
  int bad;
  initial begin
    bad = 0;
    repeat (50) begin
      if (!o.randomize()) $fatal(1, "randomize failed");
      if (o.r_sum != 8'(o.p.lo + 8'd1 + o.p.hi)) bad++;
      if (o.r_q != o.p.hi) bad++;
      if (o.r_u != (o.a ^ o.b)) bad++;
      if (o.r_arr != 8'(o.arr0 + o.arr1)) bad++;
    end
    if (bad) $fatal(1, "aggregate mismatches %0d", bad);
    $display("native aggregate functions PASS");
    repeat (20) begin
      q.s.hi = 8'($urandom_range(0, 255));
      begin
        automatic bit [7:0] hi = q.s.hi;
        if (!q.randomize()) $fatal(1, "qualified randomize failed");
        if (q.s.hi != hi) $fatal(1, "state member changed");
        if (q.s.lo >= 100 || q.r != 8'(q.s.lo - hi))
          $fatal(1, "qualified relation violated");
      end
    end
    $display("qualified structure actual PASS");
  end
endmodule
