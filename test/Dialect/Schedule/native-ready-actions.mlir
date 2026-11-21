// RUN: talos-opt %s --schedule-coalesce-native-ready -o %t
// RUN: talos-opt %t --cse | FileCheck %s
// RUN: talos-opt %t --convert-native-schedule-actions-to-llvm | FileCheck %s --check-prefix=LOWER
// Pending-mask union must respect consume, alias, observation and publication.
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<2 x i64>
  llvm.func @updates(%alias: !llvm.ptr, %ctx: !llvm.ptr) -> i64 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %zero = arith.constant 0 : i64
    // CHECK: %[[REMOVE:.*]] = arith.constant 1 : i64
    // CHECK: %[[ADD:.*]] = arith.constant 2 : i64
    // CHECK: schedule.ready.commit @__talos_aot_model_ingress_v1[0], %[[REMOVE]], %[[ADD]]
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 128 : i64, consume = false}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 128 : i64, consume = false}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 128 : i64, consume = true}
    // CHECK: llvm.load
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 128 : i64, consume = false}
    %observed = llvm.load %alias : !llvm.ptr -> i64
    // CHECK: schedule.ready.update
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 128 : i64, consume = false}
    // CHECK: schedule.transition
    // CHECK: schedule.transition
    // LOWER-COUNT-2: llvm.call @talos_rt_v1_scheduler_static_transition
    schedule.transition %ctx, %zero, %zero, %zero, %one, %zero {static_state = 1 : i64, width = 1 : i64, source_owner = #schedule.source_owner<codeUnit = 9 : i64, continuation = 0 : i64>} : (!llvm.ptr, i64, i64, i64, i64, i64) -> ()
    schedule.transition %ctx, %zero, %one, %zero, %zero, %zero {static_state = 1 : i64, width = 1 : i64, source_owner = #schedule.source_owner<codeUnit = 9 : i64, continuation = 0 : i64>} : (!llvm.ptr, i64, i64, i64, i64, i64) -> ()
    llvm.return %observed : i64
  }
}
