// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 19 : i64}"},talos-materialize-native-eval-groups)' | FileCheck %s --check-prefix=FITS
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 18 : i64}"},talos-materialize-native-eval-groups)' | FileCheck %s --check-prefix=OVER

// A ready action names its set. In LLVM IR a function shares one address of
// each set, so the inline budget charges the producer that address once: its
// constant, its update (12 per index level), its return and the address cost
// 15, the consumer 4. Both fit 19 operations; at 18 the consumer stays a call.
// FITS-LABEL: llvm.func @group()
// FITS-SAME: schedule.eval.materialized_group_calls = 2
// FITS-NOT: llvm.call
// FITS: llvm.return
// OVER-LABEL: llvm.func @group()
// OVER-SAME: schedule.eval.materialized_group_calls = 1
// OVER: llvm.call @consumer()
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<1> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @observed(0 : i32) : i32
  llvm.func @producer() attributes {schedule.eval.infallible} {
    %two = llvm.mlir.constant(2 : i64) : i64
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 64 : i64, consume = false}
    llvm.return
  }
  llvm.func @consumer() attributes {schedule.eval.infallible} {
    %out = llvm.mlir.addressof @observed : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %out : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @producer() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @consumer() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return
  }
}
