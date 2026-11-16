// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.4/18.5, 7.5, 7.10: a dynamic array or queue whose size()
// is an arithmetic function of a bounded header is sized from that bound.
// Pins size relation, grow/shrink across calls, rollback on failure and a
// four-state header.
// CHECK: array grow shrink PASS
// CHECK-NEXT: array failure rollback PASS
// CHECK-NEXT: queue grow shrink rollback PASS
// CHECK-NEXT: xz header PASS

class D;
  rand bit [7:0] len;
  rand bit [7:0] payload[];
  constraint c { len inside {[4:68]}; payload.size() == len * 2 + 3;
                 foreach (payload[i]) payload[i] inside {[1:9]}; }
endclass
class Q;
  rand bit [7:0] len;
  rand bit [7:0] payload[$];
  constraint c { len inside {[4:68]}; payload.size() == len * 2 + 3;
                 foreach (payload[i]) payload[i] inside {[1:9]}; }
endclass
class X;
  rand logic [7:0] len;
  rand bit [7:0] payload[];
  constraint c { len inside {[4:6]}; payload.size() == 8'(len) + 1;
                 foreach (payload[i]) payload[i] inside {[1:9]}; }
endclass

module top;
  D d = new;
  Q q = new;
  X x = new;
  int n, ok;
  bit [7:0] snap[$];

  function automatic bit elems_ok(bit [7:0] a[]);
    foreach (a[i]) if (a[i] < 1 || a[i] > 9) return 0;
    return 1;
  endfunction

  initial begin
    // Dynamic array: size relation holds; grow and shrink across calls.
    ok = 1;
    foreach (d.payload[i]) ok = 0;
    if (!ok) $fatal(1, "array not empty at start");
    if (!d.randomize() with { len == 4; }) $fatal(1, "d4");
    if (d.payload.size() != 11 || !elems_ok(d.payload)) $fatal(1, "d4 size");
    if (!d.randomize() with { len == 68; }) $fatal(1, "d68");
    if (d.payload.size() != 139 || !elems_ok(d.payload)) $fatal(1, "d68 size");
    if (!d.randomize() with { len == 5; }) $fatal(1, "d5");
    if (d.payload.size() != 13 || !elems_ok(d.payload)) $fatal(1, "d5 size");
    $display("array grow shrink PASS");

    // Failure leaves length, size and contents unchanged.
    snap = {};
    foreach (d.payload[i]) snap.push_back(d.payload[i]);
    if (d.randomize() with { payload[0] == 20; }) $fatal(1, "element 20 solved");
    if (d.len != 5 || d.payload.size() != 13) $fatal(1, "failure changed object");
    foreach (snap[i]) if (d.payload[i] != snap[i]) $fatal(1, "failure changed data");
    if (!d.randomize()) $fatal(1, "recovery");
    if (d.payload.size() != int'(d.len) * 2 + 3 || !elems_ok(d.payload))
      $fatal(1, "recovery size");
    $display("array failure rollback PASS");

    // Queue.
    if (!q.randomize() with { len == 68; }) $fatal(1, "q68");
    if (q.payload.size() != 139) $fatal(1, "q68 size");
    if (!q.randomize() with { len == 4; }) $fatal(1, "q4");
    if (q.payload.size() != 11) $fatal(1, "q4 size");
    foreach (q.payload[i]) if (q.payload[i] < 1 || q.payload[i] > 9) $fatal(1, "q elem");
    if (q.randomize() with { payload[0] == 20; }) $fatal(1, "q bad solved");
    if (q.len != 4 || q.payload.size() != 11) $fatal(1, "q failure changed object");
    $display("queue grow shrink rollback PASS");

    // Header that may be X/Z: results stay within the proven bound.
    for (int k = 0; k < 20; k++) begin
      if (!x.randomize()) $fatal(1, "x solve");
      if (x.payload.size() != int'(x.len) + 1 || !elems_ok(x.payload))
        $fatal(1, "x size");
    end
    $display("xz header PASS");
  end
endmodule
