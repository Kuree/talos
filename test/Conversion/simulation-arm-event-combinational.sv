// RUN: talos -emit-sim %s -o - | talos-opt --pass-pipeline='builtin.module(simulation.design(talos-sim-arm-event-combinational))' | FileCheck %s

// `always @(a or b)` waits for its first event (IEEE 1800-2023 9.4.2). It
// becomes body-first behind an armed bit that a one-shot initial copy sets at
// that first event; the block runs its body only while armed and also waits
// on the bit. The copy starts right after the block, on a private seed stream
// (18.14.1). Edge-triggered, multi-wait and delayed blocks keep
// their shape.

// CHECK: simulation.code_unit.decl {{[0-9]+}} in {{[0-9]+}} initial hierarchy "comb.$code_unit_{{[0-9]+}}.$arm" debug "" {internal}
// CHECK: %[[ARMED:.+]] = simulation.context.storage %arg0[[[ID:[0-9]+]]] : !simulation.ref<i1>
// CHECK: simulation.spawn @[[UNIT:unit_[0-9]+]](%arg0, {{.*}}, %[[ARMED]])
// CHECK-NEXT: simulation.random.initialization_leave
// CHECK-NEXT: %[[PRIVATE:.+]] = simulation.random.initialization_enter %arg0 {scope = 4 : i64}
// CHECK-NEXT: simulation.spawn @[[UNIT]].$arm(%arg0, {{.*}}, %[[ARMED]])
// CHECK-NEXT: simulation.random.initialization_leave %arg0, %[[PRIVATE]]
// CHECK: simulation.storage.decl [[ID]] in {{[0-9]+}} : i1 design {observability = 0 : i32}
// CHECK: simulation.func private @[[UNIT]](
// CHECK-SAME: schedule.armed_combinational
// CHECK-NEXT: cf.br ^[[GUARD:bb[0-9]+]]
// CHECK: simulation.suspend.any %arg1, %arg2, %[[BIT:arg[0-9]+]] edges [0, 0, 0] to ^[[GUARD]] {schedule.procedural_event_wait, schedule.repeating_always_wait
// CHECK: ^[[GUARD]]:
// CHECK-NEXT: %[[SET:.+]] = simulation.ref.load %[[BIT]]
// CHECK-NEXT: cf.cond_br %[[SET]], ^{{bb[0-9]+}}, ^{{bb[0-9]+}}
// CHECK: simulation.func private @[[UNIT]].$arm(
// CHECK: simulation.suspend.any %arg1, %arg2 edges [0, 0] to ^[[SETBB:bb[0-9]+]] {schedule.procedural_event_wait, site
// CHECK: ^[[SETBB]]:
// CHECK-NEXT: %true = arith.constant true
// CHECK-NEXT: simulation.ref.store %true to %{{.+}} : i1
// CHECK-NEXT: simulation.return
// CHECK-NOT: schedule.armed_combinational

module comb;
  logic [3:0] a = 0, b = 0, c = 0;
  logic [3:0] y, e, m, d;
  logic clk = 0;
  always @(a or b) y = a + b;
  always @(posedge clk) e = a;
  always begin @(a); @(b); m = a; end
  always @(c) begin #1 d = c; end
  final $display("%0d %0d %0d %0d %0d", y, e, m, d, $urandom);
  initial begin #1 a = 1; #1 b = 2; #1 c = 3; clk = 1; #2 $finish; end
endmodule
