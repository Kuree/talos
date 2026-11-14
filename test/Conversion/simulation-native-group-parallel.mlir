// RUN: talos-opt %s --allow-unregistered-dialect --split-input-file --mlir-disable-threading --talos-materialize-native-eval-groups -o %t.serial.mlir
// RUN: talos-opt %s --allow-unregistered-dialect --split-input-file --talos-materialize-native-eval-groups -o %t.parallel.mlir
// RUN: diff -u %t.serial.mlir %t.parallel.mlir
// RUN: FileCheck %s < %t.parallel.mlir

// Group callees are mutable. Both direct and transitive callers must see the
// callee after its ordered materialization, including the changed inline cost.
// Inlining a pre-materialization copy would exhaust the budget before @leaf.
// Each group has two members: a body only forwards between members.
module attributes {schedule.native.max_inline_ops = 5 : i64} {
  llvm.func @leaf() -> i32 attributes {schedule.eval.infallible} {
    %one = llvm.mlir.constant(1 : i32) : i32
    %two = llvm.mlir.constant(2 : i32) : i32
    %value = llvm.add %one, %two : i32
    llvm.return %value : i32
  }
  llvm.func @other() attributes {schedule.eval.infallible} {
    llvm.return
  }
  // CHECK-LABEL: llvm.func @producer()
  // CHECK-SAME: schedule.eval.materialized_group_calls = 2 : i64
  // CHECK-NOT: llvm.call
  // CHECK: llvm.return
  llvm.func @producer() -> i32 attributes {schedule.eval.infallible, schedule.eval.ranked_members = array<i32: 0, 1>} {
    %value = llvm.call @leaf() {schedule.eval.group_member = 0 : i32} : () -> i32
    llvm.call @other() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return %value : i32
  }
  // CHECK-LABEL: llvm.func @direct()
  // CHECK-NOT: llvm.call
  // CHECK: llvm.return
  llvm.func @direct() -> i32 attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    %value = llvm.call @producer() {schedule.eval.group_member = 0 : i32} : () -> i32
    llvm.call @other() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return %value : i32
  }
  llvm.func @bridge() -> i32 attributes {schedule.eval.infallible} {
    %value = llvm.call @producer() : () -> i32
    llvm.return %value : i32
  }
  // CHECK-LABEL: llvm.func @transitive()
  // CHECK: llvm.call @producer()
  // CHECK-NOT: llvm.call @bridge
  // CHECK-NOT: llvm.call @leaf
  // CHECK: llvm.return
  llvm.func @transitive() -> i32 attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    %value = llvm.call @bridge() {schedule.eval.group_member = 0 : i32} : () -> i32
    llvm.call @other() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return %value : i32
  }
}

// -----

// Candidate metadata introduces a write to @original without a call edge.
// The preceding candidate must replace its body before @original's turn.
// Its untouched slow body, including the call, becomes @original.fallback.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<1xi8>) : !llvm.array<1 x i8>
  llvm.mlir.global internal @ready(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @leaf() attributes {schedule.eval.infallible} {
    llvm.return
  }
  llvm.func @other() attributes {schedule.eval.infallible} {
    llvm.return
  }
  // CHECK-LABEL: llvm.func @original.fallback()
  // CHECK: llvm.call @leaf()
  // CHECK: llvm.call @other()
  // CHECK: llvm.return
  llvm.func @candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @original} {
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  // CHECK-LABEL: llvm.func @original()
  // CHECK-SAME: schedule.eval.control_flow_dataflow
  // CHECK-SAME: schedule.eval.dataflow_fallback = @original.fallback
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_value[0]
  // CHECK: llvm.call @original.fallback()
  llvm.func @original() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    llvm.call @leaf() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @other() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return
  }
}

// -----

// Unknown symbol scopes force candidate retention. Ordinary groups can still
// materialize their bodies, and both threading modes preserve the same symbols.
module {
  llvm.func @leaf() attributes {schedule.eval.infallible} {
    llvm.return
  }
  llvm.func @other() attributes {schedule.eval.infallible} {
    llvm.return
  }
  // CHECK-LABEL: llvm.func @group()
  // CHECK-SAME: schedule.eval.materialized_group_calls = 2 : i64
  // CHECK-NOT: llvm.call
  // CHECK: llvm.return
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @leaf() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @other() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return
  }
  // CHECK-LABEL: llvm.func @candidate()
  // CHECK-NOT: dataflow_candidate
  // CHECK: llvm.return
  llvm.func @candidate() attributes {schedule.eval.ranked_members = array<i32: 0>, schedule.eval.dataflow_candidate = @group} {
    llvm.return
  }
  "unknown.scope"() ({
    "unknown.use"() {target = @candidate} : () -> ()
  }) : () -> ()
}

// -----

// Symbol uses on a nested symbol-table root belong to the outer scope; uses
// inside its region resolve in the nested scope, including shadowed names.
module {
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0>} {
    llvm.return
  }
  // CHECK-LABEL: llvm.func @root_use()
  // CHECK-NOT: dataflow_candidate
  // CHECK: llvm.return
  llvm.func @root_use() attributes {schedule.eval.ranked_members = array<i32: 0>, schedule.eval.dataflow_candidate = @group} {
    llvm.return
  }
  // CHECK-NOT: llvm.func @shadowed
  // CHECK: module @nested
  // CHECK-SAME: test.target = @root_use
  // CHECK: llvm.func @shadowed()
  llvm.func @shadowed() attributes {schedule.eval.ranked_members = array<i32: 0>, schedule.eval.dataflow_candidate = @group} {
    llvm.return
  }
  module @nested attributes {test.target = @root_use} {
    llvm.func @shadowed() {
      llvm.return
    }
    llvm.func @caller() {
      llvm.call @shadowed() : () -> ()
      llvm.return
    }
  }
}

// -----

// A group of one member forwards nothing between members: its body stays a
// call, whatever the budget.
module {
  llvm.func @leaf() attributes {schedule.eval.infallible} {
    llvm.return
  }
  // CHECK-LABEL: llvm.func @single()
  // CHECK-NOT: materialized_group_calls
  // CHECK: llvm.call @leaf()
  // CHECK: llvm.return
  llvm.func @single() attributes {schedule.eval.ranked_members = array<i32: 0>} {
    llvm.call @leaf() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.return
  }
}

// -----

// Workers lower an independent group's schedule actions. The runtime entry
// points those calls name are declared at the group's ordered turn, as is the
// whole lowering of a group whose unspecialized batch adds a root table, so
// serial and concurrent materialization build the same module. The input
// holds no arith or cf operation: the pass itself loads the dialects that
// action and batch lowering create.
#batch = #schedule.nba_batch_layout<plan = @plan, value = @value, unknown = @unknown, dirty = @dirty, summary = @summary, ingress = @ingress, bitCount = 256, rootCount = 66, capacity = 130>
#aux = #schedule.nba_commit_layout<offset = 232, width = 8, accumulator = @aux, slots = [], consumers = []>
module {
  llvm.mlir.global external @plan() : i8
  llvm.mlir.global external @value() : !llvm.array<40 x i8>
  llvm.mlir.global external @unknown() : !llvm.array<40 x i8>
  llvm.mlir.global external @dirty() : !llvm.array<2 x i64>
  llvm.mlir.global external @summary() : i64
  llvm.mlir.global external @ingress() : !llvm.array<8 x i64>
  llvm.mlir.global external @aux() : !llvm.array<136 x i8>
  llvm.mlir.global external @changed() : i8
  llvm.func @first() attributes {schedule.eval.infallible} {
    llvm.return
  }
  llvm.func @second() attributes {schedule.eval.infallible} {
    llvm.return
  }
  // CHECK-DAG: llvm.func @talos_rt_v1_scheduler_static_transition(
  // CHECK-DAG: llvm.func @talos_rt_v1_static_nba_batch_guard(
  // CHECK-DAG: llvm.func @talos_rt_v1_static_nba_commit_batch(
  // CHECK-DAG: llvm.mlir.global internal constant @__talos_nba_batch_roots
  // CHECK-LABEL: llvm.func @lowered(
  // CHECK-NOT: llvm.call @first
  // CHECK: llvm.call @talos_rt_v1_scheduler_static_transition(
  // CHECK: llvm.call @talos_rt_v1_static_nba_batch_guard(
  // CHECK-NOT: schedule.nba
  // CHECK-NOT: schedule.transition
  // CHECK: llvm.return
  llvm.func @lowered(%ctx: !llvm.ptr) attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @first() {schedule.eval.group_member = 0 : i32} : () -> ()
    %zero = llvm.mlir.constant(0 : i64) : i64
    %one = llvm.mlir.constant(1 : i64) : i64
    schedule.transition %ctx, %zero, %zero, %zero, %one, %zero {static_state = 1 : i64, width = 1 : i64} : (!llvm.ptr, i64, i64, i64, i64, i64) -> ()
    llvm.call @second() {schedule.eval.group_member = 1 : i32} : () -> ()
    %region = llvm.mlir.constant(2 : i32) : i32
    %changed = llvm.mlir.addressof @changed : !llvm.ptr
    %status = schedule.nba.batch %ctx, %region, %changed {
      schedule.nba.commit 2 {layout = #aux}
      schedule.nba.yield
    } {layout = #batch} : (!llvm.ptr, i32, !llvm.ptr) -> i32
    llvm.return
  }
  // CHECK-LABEL: llvm.func @deferred(
  // CHECK-NOT: llvm.call @first
  // CHECK: llvm.call @talos_rt_v1_static_nba_commit_batch(
  // CHECK-NOT: schedule.
  // CHECK: llvm.return
  llvm.func @deferred(%ctx: !llvm.ptr) attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @first() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @second() {schedule.eval.group_member = 1 : i32} : () -> ()
    %region = llvm.mlir.constant(2 : i32) : i32
    %changed = llvm.mlir.addressof @changed : !llvm.ptr
    %status = schedule.nba.batch %ctx, %region, %changed {
      schedule.nba.commit 1
      schedule.nba.yield
    } : (!llvm.ptr, i32, !llvm.ptr) -> i32
    llvm.return
  }
}
