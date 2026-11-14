// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: not %t --seed=13 2>&1 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.9/18.5.11: the implicit ordering of a function call's
// arguments is taken from the live constraints only. Calls in mutually
// exclusive branches are not a cycle; a cycle among live calls is a run-time
// error (the process exits non-zero, hence `not`) and randomize() returns 0.
// CHECK-DAG: error: solve before ordering of the active constraint blocks contains a cycle
// CHECK-DAG: exclusive PASS
// CHECK-DAG: inactive PASS
// CHECK-DAG: live cycle PASS

class C;
  rand bit [7:0] x, y;
  bit enabled;
  function bit [7:0] inc(bit [7:0] v); return v + 8'd1; endfunction
  constraint exclusive { if (enabled) x == inc(y); else y == inc(x); }
endclass
class D;
  rand bit [7:0] x, y;
  bit enabled;
  function bit [7:0] inc(bit [7:0] v); return v + 8'd1; endfunction
  constraint live { x == inc(y); if (enabled) y == inc(x); }
endclass
module top;
  C c = new; D d = new; int ok;
  initial begin
    repeat (8) begin
      c.enabled = 1; ok = c.randomize();
      if (!ok || c.x != c.y + 8'd1) $fatal(1, "enabled");
      c.enabled = 0; ok = c.randomize();
      if (!ok || c.y != c.x + 8'd1) $fatal(1, "disabled");
    end
    $display("exclusive PASS");
    d.enabled = 0; ok = d.randomize();
    if (!ok || d.x != d.y + 8'd1) $fatal(1, "live off");
    $display("inactive PASS");
    d.enabled = 1; ok = d.randomize();
    if (ok) $fatal(1, "cycle"); $display("live cycle PASS");
  end
endmodule
