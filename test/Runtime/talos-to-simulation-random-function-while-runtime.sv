// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 12.7.4, 12.7.5 and 18.5.11: while and do...while loops with
// provable progress (modular counter or logical right shift) in a constraint
// function agree with ordinary execution: the do...while body runs once even
// when its test is initially false, continue still reaches the counter
// update, break leaves the loop, and a failed solve leaves the object intact.
// CHECK: procedural while PASS
// CHECK-NEXT: shift loop PASS
// CHECK-NEXT: continue/break PASS
// CHECK-NEXT: failed solve PASS

function automatic int ones(bit [3:0] word);
  int total = 0;
  while (word != 0) begin total += word[0]; word >>= 1; end
  return total;
endfunction

// Do...while: zero input still counts the first pass.
function automatic int passes(bit [3:0] word);
  int total = 0;
  do begin total++; word >>= 1; end while (word != 0);
  return total;
endfunction

// Skips the first sum with continue (the counter still advances), then
// either breaks after 2 or finishes with 2 + 3 + 4.
function automatic int skip(bit [3:0] limit);
  int total = 0, n = 0;
  while (n < 4) begin
    n++;
    if (n == 1) continue;
    if (n == 3 && limit[0]) break;
    total += n;
  end
  return total;
endfunction

class C;
  rand bit [3:0] x, y;
  rand bit [4:0] p, s;
  bit force_fail;
  constraint c1 { x == ones(y); }
  constraint c2 { p == passes(y); s == skip(y); }
  constraint c3 { if (force_fail) x == 0 && y != 0; }
endclass

module top;
  C object = new;
  bit [3:0] ox, oy;
  int fails = 0;
  initial begin
    if (ones(0) != 0 || ones(8) != 1 || ones(15) != 4) $fatal(1, "ones");
    if (passes(0) != 1 || passes(8) != 4 || passes(15) != 4) $fatal(1, "passes");
    if (skip(0) != 9 || skip(1) != 2) $fatal(1, "skip");
    $display("procedural while PASS");
    repeat (64) begin
      if (!object.randomize()) $fatal(1, "randomize failed");
      if (object.x != $countones(object.y)) $fatal(1, "ones mismatch");
      if (object.p != passes(object.y)) $fatal(1, "passes mismatch");
    end
    $display("shift loop PASS");
    repeat (16) begin
      if (!object.randomize()) $fatal(1, "randomize failed");
      if (object.s != skip(object.y)) $fatal(1, "skip mismatch");
    end
    $display("continue/break PASS");
    object.force_fail = 1;
    ox = object.x; oy = object.y;
    repeat (8) begin
      if (object.randomize()) $fatal(1, "contradiction solved");
      if (object.x != ox || object.y != oy) $fatal(1, "fields changed");
    end
    $display("failed solve PASS");
  end
endmodule
