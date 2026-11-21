// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 10 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=FITS
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 9 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=OVER

// The group dataflow budget counts an eval mask word access as its LLVM form:
// the access, a byte GEP to word 1, and the mask's address once per function.
// The candidate is its two word accesses (four operations), the address and
// five other operations: ten fit 10 operations and not 9. The accepted
// group's guard reads its members' pending proof bits as a mask word.
// FITS-LABEL: llvm.func @group()
// FITS-SAME: schedule.eval.control_flow_dataflow
// FITS: schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
// FITS: llvm.cond_br
// OVER-LABEL: llvm.func @group()
// OVER-NOT: schedule.eval.control_flow_dataflow
// OVER-SAME: schedule.eval.group_ingress
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @slow(0 : i32) : i32
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %p = llvm.mlir.addressof @slow : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %p : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @group} {
    %pending = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[1]
    %zero = llvm.mlir.constant(0 : i64) : i64
    %unknown = llvm.icmp "ne" %pending, %zero : i64
    llvm.cond_br %unknown, ^clear, ^done
  ^clear:
    schedule.mask.store %zero, @__talos_eval_promotion_pending_mask_v1[1]
    llvm.br ^done
  ^done:
    llvm.return
  }
}
