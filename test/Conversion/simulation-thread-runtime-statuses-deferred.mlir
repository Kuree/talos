// RUN: talos-opt %s --split-input-file --talos-sim-thread-runtime-statuses | FileCheck %s

// Queueing a pending deferred assertion report (IEEE 1800-2023 16.4.1) is a
// cold runtime exit of the activation, like $error: a call to a runtime entry
// the catalog marks ReportsStatus gives the function, and each caller, the
// runtime status channel. Control lowering has already turned the enqueue
// into its ABI call. Other runtime calls do not.

// CHECK-LABEL: simulation.func private @leaf(
// CHECK-SAME: -> i32
// CHECK: llvm.call @talos_rt_v1_deferred_enqueue(
// CHECK-LABEL: simulation.func private @caller(
// CHECK-SAME: -> i32
// CHECK: %[[BITS:.*]] = simulation.call @leaf(
// CHECK-NEXT: %[[STATUS:.*]] = runtime.status.from_bits %[[BITS]]
// CHECK-NEXT: runtime.status.is %[[STATUS]], <ok>
module {
  simulation.design @d {
    llvm.func @talos_rt_v1_deferred_enqueue(!llvm.ptr, i64) -> i64
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "d.leaf"
    simulation.code_unit.decl 2 in 0 function hierarchy "d.caller"
    simulation.func private @leaf(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      %runtime = llvm.mlir.zero : !llvm.ptr
      %report = llvm.mlir.constant(7 : i64) : i64
      %ticket = llvm.call @talos_rt_v1_deferred_enqueue(%runtime, %report) : (!llvm.ptr, i64) -> i64
      simulation.return
    }
    simulation.func private @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      simulation.call @leaf(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.func private @leaf(
// CHECK-SAME: -> i32
// CHECK: llvm.call @talos_rt_v1_deferred_enqueue_for_assertion(
module {
  simulation.design @d {
    llvm.func @talos_rt_v1_deferred_enqueue_for_assertion(!llvm.ptr, i64, i64) -> i64
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "d.leaf"
    simulation.func private @leaf(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      %runtime = llvm.mlir.zero : !llvm.ptr
      %report = llvm.mlir.constant(7 : i64) : i64
      %assertion = llvm.mlir.constant(3 : i64) : i64
      %ticket = llvm.call @talos_rt_v1_deferred_enqueue_for_assertion(%runtime, %report, %assertion) : (!llvm.ptr, i64, i64) -> i64
      simulation.return
    }
  }
}

// -----

// Claiming a deferred assertion site's first execution in a time slot queues
// no report.
// CHECK-LABEL: simulation.func private @leaf(
// CHECK-NOT: -> i32
// CHECK: llvm.call @talos_rt_v1_deferred_once(
// CHECK-NEXT: simulation.return{{$}}
module {
  simulation.design @d {
    llvm.func @talos_rt_v1_deferred_once(!llvm.ptr, i64) -> i32
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "d.leaf"
    simulation.func private @leaf(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      %runtime = llvm.mlir.zero : !llvm.ptr
      %report = llvm.mlir.constant(7 : i64) : i64
      %done = llvm.call @talos_rt_v1_deferred_once(%runtime, %report) : (!llvm.ptr, i64) -> i32
      simulation.return
    }
  }
}
