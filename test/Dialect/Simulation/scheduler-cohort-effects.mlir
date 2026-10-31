// RUN: talos-opt %s --canonicalize --cse | FileCheck %s
// IEEE 1801-2018 6.50/9.7: cohort reads may be commoned within one actor,
// but a scheduler write or suspension must prevent reuse of an old token.
// CHECK-LABEL: simulation.func @cohort_effects
// CHECK: %[[BEFORE:.*]] = simulation.scheduler.cohort %[[CTX:.*]]
// CHECK-NEXT: simulation.nba.enqueue %[[BEFORE]]
// CHECK-NEXT: %[[QUEUED:.*]] = simulation.scheduler.cohort %[[CTX]]
// CHECK-NEXT: simulation.nba.enqueue %[[QUEUED]]
// CHECK: simulation.suspend.delay
// CHECK: %[[AFTER:.*]] = simulation.scheduler.cohort %[[CTX]]
// CHECK-NEXT: simulation.ref.store %[[AFTER]]
module {
  simulation.func @cohort_effects(
      %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
      %target: !simulation.ref<i64> {simulation.capture_kind = 1 : i32})
      attributes {entry_kind = 12 : i32} {
    %before = simulation.scheduler.cohort %ctx
    simulation.nba.enqueue %before to %target : (i64, !simulation.ref<i64>) -> ()
    %queued = simulation.scheduler.cohort %ctx
    simulation.nba.enqueue %queued to %target : (i64, !simulation.ref<i64>) -> ()
    %zero = simulation.time.constant 0
    simulation.suspend.delay %zero to ^resume
  ^resume:
    %after = simulation.scheduler.cohort %ctx
    simulation.ref.store %after to %target : i64, !simulation.ref<i64>
    simulation.return
  }
}
