// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=3' -o /dev/null

// IEEE 1800-2023 16.12: disable iff uses unsampled values and cancels only
// live attempts. An NBA disable pulse that ends before Observed must clear
// older attempts before a fresh attempt starts, even if the pulse occurs
// before the first attempt. The canceller therefore resumes in Active and
// clears live attempts before Observed, while assertion evaluation and user
// actions retain their phases.
// 4.4.2.5, 16.14.3, 20.11: a successful attempt completes in Observed and
// queues its action in Reactive. A disable that the Active canceller has not
// serviced before then revokes the queued report: the Reactive revoker bumps
// the report epoch only if the canceller event is still pending. Every
// disable iff assertion, including a one-cycle property, gets both actors.

// The multi-cycle report guards on both the Kill epoch and the disable epoch.
// CHECK-LABEL: simulation.func private @unit_2.fork.{{[0-9.]+}}(
// CHECK-SAME: %arg5: i64
// CHECK-SAME: schedule.concurrent_report
// CHECK: simulation.assert.kill_epoch
// CHECK: arith.cmpi eq, {{.*}}, %arg5
// CHECK: [[U2_CURRENT:%.*]] = simulation.ref.load %arg2
// CHECK: arith.cmpi eq, [[U2_CURRENT]], %arg3
// CHECK: simulation.ref.store
// CHECK: simulation.return
// The Active canceller clears the live attempt state and has no epoch.
// CHECK-LABEL: simulation.func private @unit_2.$concurrent_cancel.
// CHECK-SAME: %arg4: !simulation.ref<i64>
// CHECK-SAME: ) attributes
// CHECK-SAME: home_region = 2 : i32
// CHECK-SAME: schedule.concurrent_cancel
// CHECK-SAME: schedule.priority_signal_resume
// CHECK: simulation.suspend.observe
// CHECK-SAME: resume_region = 2 : i32
// CHECK-SAME: schedule.concurrent_cancel_level_true
// CHECK: simulation.ref.store {{.*}} to %arg4
// CHECK-NOT: simulation.ref.store
// CHECK-NOT: arith.addi
// The Reactive revoker revokes queued reports only when the canceller event is
// still pending, i.e. a transition the canceller has not serviced.
// CHECK-LABEL: simulation.func private @unit_2.$concurrent_revoke.
// CHECK-SAME: %arg4: !simulation.ref<i64>
// CHECK-SAME: %arg5: !simulation.process
// CHECK-SAME: home_region = 10 : i32
// CHECK: simulation.suspend.observe
// CHECK-SAME: resume_region = 10 : i32
// CHECK: [[U2_PENDING:%.*]] = simulation.process.event_pending %arg5
// CHECK: [[U2_EPOCH:%.*]] = simulation.ref.load %arg4
// CHECK: [[U2_BIT:%.*]] = arith.extui [[U2_PENDING]] : i1 to i64
// CHECK: [[U2_NEXT_EPOCH:%.*]] = arith.addi [[U2_EPOCH]], [[U2_BIT]]
// CHECK: simulation.ref.store [[U2_NEXT_EPOCH]] to %arg4
// Evaluation stays Observed and Kill still clears live attempt state.
// CHECK-LABEL: simulation.func private @unit_2(
// CHECK-SAME: home_region = 8 : i32
// CHECK: [[U2_CANCEL:%.*]] = simulation.spawn @unit_2.$concurrent_cancel.
// CHECK: simulation.spawn @unit_2.$concurrent_revoke.{{.*}}[[U2_CANCEL]]
// CHECK: simulation.suspend.edge
// CHECK-SAME: resume_region = 8 : i32
// CHECK: simulation.assert.kill_epoch {{.*}} {simulation.concurrent_kill_epoch_check}
// CHECK: simulation.ref.store
// CHECK: simulation.spawn @unit_2.fork.{{[0-9.]+}}(%arg0, %arg5, {{.*}})
// A one-cycle property has no live state across Observed evaluations, but its
// queued report still needs the disable epoch, so it gets both actors.
// CHECK-LABEL: simulation.func private @unit_3.fork.
// CHECK-SAME: %arg3: i64
// CHECK-SAME: schedule.concurrent_report
// CHECK: [[U3_CURRENT:%.*]] = simulation.ref.load %arg2
// CHECK: arith.cmpi eq, [[U3_CURRENT]], %arg3
// CHECK-LABEL: simulation.func private @unit_3.$concurrent_cancel.
// CHECK-SAME: %arg4: !simulation.ref<i64>
// CHECK-SAME: ) attributes
// CHECK-SAME: home_region = 2 : i32
// CHECK-SAME: schedule.concurrent_cancel
// CHECK: simulation.suspend.observe
// CHECK-SAME: resume_region = 2 : i32
// CHECK: simulation.ref.store {{.*}} to %arg4
// CHECK-NOT: simulation.ref.store
// CHECK-NOT: arith.addi
// CHECK-LABEL: simulation.func private @unit_3.$concurrent_revoke.
// CHECK-SAME: %arg4: !simulation.ref<i64>
// CHECK-SAME: %arg5: !simulation.process
// CHECK-SAME: home_region = 10 : i32
// CHECK: simulation.suspend.observe
// CHECK-SAME: resume_region = 10 : i32
// CHECK: [[U3_PENDING:%.*]] = simulation.process.event_pending %arg5
// CHECK: [[U3_EPOCH:%.*]] = simulation.ref.load %arg4
// CHECK: [[U3_BIT:%.*]] = arith.extui [[U3_PENDING]] : i1 to i64
// CHECK: [[U3_NEXT_EPOCH:%.*]] = arith.addi [[U3_EPOCH]], [[U3_BIT]]
// CHECK: simulation.ref.store [[U3_NEXT_EPOCH]] to %arg4
// CHECK-LABEL: simulation.func private @unit_3(
// CHECK-SAME: home_region = 8 : i32
// CHECK: [[U3_CANCEL:%.*]] = simulation.spawn @unit_3.$concurrent_cancel.
// CHECK: simulation.spawn @unit_3.$concurrent_revoke.{{.*}}[[U3_CANCEL]]
// CHECK: simulation.suspend.edge
// CHECK: simulation.logic.is_true
// CHECK: simulation.spawn @unit_3.fork.

module concurrent_cancel_phases(
    input var logic clk, kill, launch, ack);
  int hits = 0;
  initial $assertkill(0, attempt);
  attempt: cover property (@(posedge clk) disable iff (kill) launch ##1 ack)
    hits = hits + 1;
  completed: cover property (@(posedge clk) disable iff (kill) launch)
    hits = hits + 1;
endmodule
