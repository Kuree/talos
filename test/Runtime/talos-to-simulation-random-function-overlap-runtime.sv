// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11, 18.5.12: a function's argument path and its result
// target may overlap inside one rand variable. Only the argument bits are
// solved first; the remaining target bits keep a dependency on the call, and a
// second call consuming that target is ordered after it. No false ordering
// cycle arises, so every randomize() succeeds and every relation holds.
// CHECK: constant overlap 1
// CHECK-NEXT: indexed overlap 1
// CHECK-NEXT: chained calls 1

function automatic bit [1:0] inc(bit [1:0] w);
  return w + 2'd1;
endfunction

function automatic bit [1:0] inv(bit [1:0] w);
  return ~w;
endfunction

class K;  // v[1:0] is the target, v[3:2] the argument, same variable
  rand bit [3:0] v;
  constraint c { v[1:0] == inc(v[3:2]); }
endclass

class I;  // the same with state-indexed windows
  rand bit [3:0] v;
  int s = 2, t = 0;
  constraint c { v[t +: 2] == inc(v[s +: 2]); }
endclass

class C;  // r consumes the target bits of the first call
  rand bit [3:0] v;
  rand bit [1:0] r;
  constraint c1 { v[1:0] == inc(v[3:2]); }
  constraint c2 { r == inv(v[1:0]); }
endclass

module top;
  K k = new;
  I i = new;
  C c = new;
  bit valid;

  initial begin
    valid = 1;
    repeat (64) begin
      valid &= k.randomize() && k.v[1:0] == k.v[3:2] + 2'd1;
    end
    if (!valid) $fatal(1, "constant overlap");
    $display("constant overlap 1");

    valid = 1;
    repeat (64) begin
      valid &= i.randomize() && i.v[1:0] == i.v[3:2] + 2'd1;
    end
    if (!valid) $fatal(1, "indexed overlap");
    $display("indexed overlap 1");

    valid = 1;
    repeat (64) begin
      valid &= c.randomize() && c.v[1:0] == c.v[3:2] + 2'd1 &&
               c.r == ~c.v[1:0];
    end
    if (!valid) $fatal(1, "chained calls");
    $display("chained calls 1");
  end
endmodule
