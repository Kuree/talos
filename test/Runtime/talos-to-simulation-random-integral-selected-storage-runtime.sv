// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11, 18.5.9, 7.4, 11.5.1: a constraint-function actual or
// result target that selects storage through a state index (array element,
// packed bit, struct member) orders exactly that storage before the call.
// "x == flip(sel)" with "x == 1" then fails about half of the draws, and a failed
// randomize() leaves every field unchanged. Invalid selections make it fail.
// CHECK: array element ordered 1
// CHECK-NEXT: packed bit ordered 1
// CHECK-NEXT: struct member ordered 1
// CHECK-NEXT: selected target ordered 1
// CHECK-NEXT: x index fails 1
// CHECK-NEXT: out-of-range index fails 1
// CHECK-NEXT: constant invalid path fails 1

typedef struct packed { bit a; bit b; } pair_t;

function automatic bit flip(bit v);
  return !v;
endfunction

class A;  // array element actual
  rand bit y[2];
  rand bit x;
  int idx = 1;
  constraint c { x == flip(y[idx]); x == 1'b1; }
endclass

class P;  // packed bit actual
  rand bit [3:0] v;
  rand bit x;
  int idx = 2;
  constraint c { x == flip(v[idx]); x == 1'b1; }
endclass

class S;  // struct member of a selected array element
  rand pair_t s[2];
  rand bit x;
  int idx = 1;
  constraint c { x == flip(s[idx].b); x == 1'b1; }
endclass

class T;  // selected storage as the result target
  rand bit y;
  rand bit t[2];
  int idx = 0;
  constraint c { t[idx] == flip(y); t[idx] == 1'b1; }
endclass

class X;  // unknown and out-of-range indices
  rand bit y[2];
  rand bit x;
  logic [1:0] idx = 2'b1x;
  constraint c { x == flip(y[idx]); x == 1'b1; }
endclass

class K;  // constant index outside the array: invalid storage path
  rand bit y[2];
  rand bit x;
  constraint c { x == flip(y[5]); }
endclass

module top;
  K k = new;
  A a = new;
  P p = new;
  S s = new;
  T t = new;
  X xo = new;
  int ok, failed;
  bit valid, same;
  bit oy0, oy1, ox;
  bit [3:0] ov;
  pair_t o0, o1;

  initial begin
    valid = 1;
    repeat (256) begin
      oy0 = a.y[0]; oy1 = a.y[1]; ox = a.x;
      if (a.randomize()) begin
        ok++;
        valid &= a.x == 1 && a.y[1] == 0;
      end else begin
        failed++;
        valid &= a.y[0] == oy0 && a.y[1] == oy1 && a.x == ox;
      end
    end
    valid &= failed >= 96 && failed <= 160 && ok + failed == 256;
    if (!valid) $fatal(1, "array element ordering %0d/%0d", ok, failed);
    $display("array element ordered 1");

    valid = 1; ok = 0; failed = 0;
    repeat (256) begin
      ov = p.v;
      if (p.randomize()) begin
        ok++;
        valid &= p.x == 1 && p.v[2] == 0;
      end else begin
        failed++;
        valid &= p.v == ov;
      end
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "packed bit ordering %0d/%0d", ok, failed);
    $display("packed bit ordered 1");

    valid = 1; ok = 0; failed = 0;
    repeat (256) begin
      o0 = s.s[0]; o1 = s.s[1];
      if (s.randomize()) begin
        ok++;
        valid &= s.x == 1 && s.s[1].b == 0;
      end else begin
        failed++;
        valid &= s.s[0] == o0 && s.s[1] == o1;
      end
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "struct member ordering %0d/%0d", ok, failed);
    $display("struct member ordered 1");

    valid = 1; ok = 0; failed = 0;
    repeat (256) begin
      if (t.randomize()) begin
        ok++;
        valid &= t.t[0] == 1 && t.y == 0;
      end else failed++;
    end
    valid &= failed >= 96 && failed <= 160;
    if (!valid) $fatal(1, "selected target ordering %0d/%0d", ok, failed);
    $display("selected target ordered 1");

    // An unknown index selects no storage; the call cannot be evaluated.
    valid = 1;
    repeat (8) valid &= !xo.randomize();
    if (!valid) $fatal(1, "X index accepted");
    $display("x index fails 1");

    xo.idx = 2;  // beyond the two elements
    valid = 1;
    repeat (8) valid &= !xo.randomize();
    if (!valid) $fatal(1, "out-of-range index accepted");
    $display("out-of-range index fails 1");

    valid = 1;
    repeat (8) valid &= !k.randomize();
    if (!valid) $fatal(1, "constant out-of-range path accepted");
    $display("constant invalid path fails 1");
  end
endmodule
