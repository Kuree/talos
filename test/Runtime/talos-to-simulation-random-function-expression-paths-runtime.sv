// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: not %t --seed=13 2>&1 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.9/18.5.11 with 11.4.11: a function actual selecting a
// rand field through state (conditional or array index) orders only the
// selected field before the call, not the whole aggregate. An X selector
// merges both arms bitwise. A cycle through the selected arm is a run-time
// error (hence `not`); the unselected arm creates none.
// CHECK-DAG: error: solve before ordering of the active constraint blocks contains a cycle
// CHECK-DAG: conditional PASS
// CHECK-DAG: indexed PASS
// CHECK-DAG: unselected PASS
// CHECK-DAG: xselect PASS
// CHECK-DAG: selected cycle PASS

class C;
  rand bit [7:0] a, b, y, z;
  rand bit [7:0] arr[3];
  bit sel;
  int idx;
  function bit [7:0] inc(bit [7:0] v); return v + 8'd1; endfunction
  constraint cond { y == inc(sel ? a : b); }
  constraint indexed { z == inc(arr[idx]); }
  constraint pin { a == 8'd10; b == 8'd20; }
endclass

// a is ordered after y by its own constraint; that is only a cycle when the
// call actually selects a.
class D;
  rand bit [7:0] a, b, y;
  bit sel;
  function bit [7:0] inc(bit [7:0] v); return v + 8'd1; endfunction
  constraint back { y == inc(sel ? a : b); a == inc(y); }
endclass

class X;
  rand bit [7:0] a, b, y;
  logic xsel;
  function bit [7:0] inc(bit [7:0] v); return v + 8'd1; endfunction
  constraint merge { y == inc(xsel ? a : b); a == 8'd10; }
endclass

module top;
  C c = new; D d = new; X x = new; int ok;
  initial begin
    c.sel = 1; c.idx = 1; ok = c.randomize();
    if (!ok || c.y != 8'd11 || c.z != c.arr[1] + 8'd1) $fatal(1, "sel1");
    c.sel = 0; c.idx = 2; ok = c.randomize();
    if (!ok || c.y != 8'd21 || c.z != c.arr[2] + 8'd1) $fatal(1, "sel0");
    $display("conditional PASS");
    $display("indexed PASS");
    d.sel = 0; ok = d.randomize();
    if (!ok || d.y != d.b + 8'd1 || d.a != d.y + 8'd1) $fatal(1, "unselected");
    $display("unselected PASS");
    // The X merge keeps bits where the arms agree on 1 and zeroes the rest.
    x.xsel = 1'bx; ok = x.randomize();
    if (!ok || x.y != (x.a & x.b) + 8'd1) $fatal(1, "xselect");
    $display("xselect PASS");
    d.sel = 1; ok = d.randomize();
    if (ok) $fatal(1, "cycle");
    $display("selected cycle PASS");
  end
endmodule
