// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11: random arguments of a pure function are solved
// first and the call result is then state. The long bodies are executed
// natively between stages (not expanded). Pins: result relation after many
// randomize calls, reuse that still tracks changed body-only state, failure
// leaving fields unchanged, and rand_mode/constraint_mode being respected.
// CHECK: stage PASS
// CHECK-NEXT: bias PASS
// CHECK-NEXT: fail PASS
// CHECK-NEXT: modes PASS

class C;
  rand bit [7:0] x, y, k;
  rand bit [3:0] s;
  bit [7:0] bias = 0;

  function automatic bit [7:0] f(bit [7:0] v);
    bit [7:0] acc = 0;
    for (int i = 0; i < 513; i++) acc = acc + v;
    return acc + bias;
  endfunction
  constraint cx { x < 16; }
  constraint cs { s inside {[0:3]}; s < 4; }
  constraint cf { y == f(x); }
  constraint cg { k == f(s); }
endclass

module top;
  C o = new;
  initial begin
    bit differs;
    repeat (20) begin
      if (!o.randomize()) $fatal(1, "randomize failed");
      if (o.x >= 16 || o.y !== 8'(513 * o.x)) $fatal(1, "stage x=%0d y=%0d", o.x, o.y);
      if (o.k !== 8'(513 * o.s)) $fatal(1, "stage s=%0d k=%0d", o.s, o.k);
    end
    $display("stage PASS");
    // The accepted result must not be reused once body-only state changes.
    o.bias = 8'd7;
    repeat (5) begin
      if (!o.randomize()) $fatal(1, "bias randomize failed");
      if (o.y !== 8'(513 * o.x + 7)) $fatal(1, "bias y=%0d x=%0d", o.y, o.x);
    end
    $display("bias PASS");
    // A contradictory result constraint fails; no field is published.
    begin
      bit ok;
      static C p = new;
      p.bias = 8'd0;
      ok = p.randomize() with { y != f(x); };
      if (ok) $fatal(1, "contradiction accepted");
      if (p.x !== 0 || p.y !== 0 || p.k !== 0) $fatal(1, "failure changed fields");
    end
    $display("fail PASS");
    // A rand_mode(0) argument is state; a disabled block drops its relation.
    o.bias = 0;
    o.x.rand_mode(0);
    o.x = 8'd9;
    if (!o.randomize() || o.x !== 8'd9 || o.y !== 8'(513 * 9)) $fatal(1, "rand_mode");
    o.cf.constraint_mode(0);
    differs = 0;
    repeat (16) begin
      if (!o.randomize() || o.x !== 8'd9) $fatal(1, "constraint_mode");
      if (o.y !== 8'(513 * 9)) differs = 1;
    end
    if (!differs) $fatal(1, "disabled block still constrains y");
    $display("modes PASS");
  end
endmodule
