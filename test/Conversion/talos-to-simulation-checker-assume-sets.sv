// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DGLOBAL %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=GLOBAL

// IEEE 1800-2023 17.7.2, on its example. F1's assume set holds u3 and F1.B1.u1,
// which reads q through the formal x, and leaves out u4 for its const cast actual.
// F1 solves q together with its child's m. B1's set holds u1 and u2, and for it q
// is an input: F1 solves that with u3, which B1 does not see, so whichever of the
// two runs last leaves every assumption of the other holding.
`ifndef GLOBAL
module top;
  bit mclk, v1, v2;
  checker c1(bit fclk, bit a, bit b);
    checker c2(bit bclk, bit x, bit y);
      rand bit m, n;
      u1: assume property (@(posedge bclk) x == m);
      u2: assume property (@(posedge bclk) y != n);
    endchecker
    rand bit q;
    bit r;
    c2 B1(fclk, q + r, r);
    always_ff @(posedge fclk) r <= a || q;
    u3: assume property (@(posedge fclk) a != q);
    u4: assume property (@(posedge fclk) b == r);
  endchecker
  c1 F1(mclk, v1, const'(v2));
endmodule
`else
// A clocking block's event fires in the Observed region (14.13), too late for a
// solve, which so waits on the signal behind the global clock.
checker observer(bit reset);
  default clocking @$global_clock; endclocking
  rand bit flag;
  m1: assume property (reset |=> !flag);
endchecker
module top;
  bit clk, reset;
  global clocking @(posedge clk); endclocking
  observer model(reset);
endmodule
`endif

// CHECK-DAG: simulation.storage.decl 3 in {{.*}}"top.F1.q"
// CHECK-DAG: simulation.storage.decl 5 in {{.*}}"top.F1.B1.m"
// CHECK-DAG: simulation.storage.decl 6 in {{.*}}"top.F1.B1.n"

// B1 assigns only its own variables.
// CHECK: simulation.func private @unit_8(
// CHECK-SAME: %[[B1_M:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 5 : i64}
// CHECK-SAME: %[[B1_N:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 6 : i64}
// CHECK: simulation.random.solve
// CHECK: simulation.ref.store %{{[0-9]+}} to %[[B1_M]]
// CHECK-NEXT: simulation.ref.store %{{[0-9]+}} to %[[B1_N]]
// CHECK-NOT: simulation.ref.store

// F1 assigns its q and its child's m, and leaves n alone.
// CHECK: simulation.func private @unit_9(
// CHECK-SAME: %[[F1_Q:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 3 : i64}
// CHECK-SAME: %[[F1_M:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 5 : i64}
// CHECK: simulation.random.solve
// CHECK: simulation.ref.store %{{[0-9]+}} to %[[F1_Q]]
// CHECK-NEXT: simulation.ref.store %{{[0-9]+}} to %[[F1_M]]
// CHECK-NOT: simulation.ref.store

// GLOBAL: simulation.storage.decl 0 in {{.*}}"top.clk"
// GLOBAL: simulation.func private @[[SOLVE:unit_[0-9]+]](
// GLOBAL-SAME: %[[CLOCK:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 0 : i64}
// GLOBAL: simulation.suspend.edge posedge %[[CLOCK]]
// GLOBAL: simulation.random.solve
