// RUN: talos-opt %s --split-input-file --talos-materialize-native-eval-groups | FileCheck %s --implicit-check-not=predicated_dataflow --implicit-check-not=dataflow_executor

// A candidate with an effect or an access the slot model cannot name has no
// dense form. Its CFG executes each operation where the member bodies do, and
// speculates nothing (IEEE 1800-2023 4.3, 4.6, 6.3.1), so the group still gets
// a single entry: it refreshes unqueried proofs there, and a failed proof falls
// back to the ordinary per-member body.

// CHECK-LABEL: llvm.func @call_group()
// CHECK-SAME: schedule.eval.control_flow_dataflow
// CHECK-SAME: schedule.eval.dataflow_fallback = @call_group.fallback
// CHECK-SAME: schedule.eval.refresh_group_proofs
// CHECK: llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1
// CHECK: llvm.cond_br
// CHECK: llvm.call @effect()
// CHECK: llvm.call @call_group.fallback()
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @ready(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @effect()
  llvm.func @call_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @call_group} {
    llvm.call @effect() : () -> ()
    llvm.return
  }
  llvm.func @call_group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    llvm.return
  }
}

// -----

// Division can trap, so the dense form may not compute it on an inactive path.
// CHECK-LABEL: llvm.func @divide_group()
// CHECK-SAME: schedule.eval.control_flow_dataflow
// CHECK-SAME: schedule.eval.refresh_group_proofs
// CHECK: llvm.udiv
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @ready(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @divide_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @divide_group} {
    %base = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %value = llvm.load %base : !llvm.ptr -> i8
    %result = llvm.udiv %value, %value : i8
    llvm.store %result, %base : i8, !llvm.ptr
    llvm.return
  }
  llvm.func @divide_group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    llvm.return
  }
}

// -----

// A load past the state plane has no slot.
// CHECK-LABEL: llvm.func @range_group()
// CHECK-SAME: schedule.eval.control_flow_dataflow
// CHECK-SAME: schedule.eval.refresh_group_proofs
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @ready(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @range_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @range_group} {
    %base = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %byte = llvm.getelementptr %base[63] : (!llvm.ptr) -> !llvm.ptr, i8
    %value = llvm.load %byte : !llvm.ptr -> i16
    llvm.store %value, %base : i16, !llvm.ptr
    llvm.return
  }
  llvm.func @range_group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    llvm.return
  }
}

// -----

// A store through a computed address has no slot either.
// CHECK-LABEL: llvm.func @opaque_group()
// CHECK-SAME: schedule.eval.control_flow_dataflow
// CHECK-SAME: schedule.eval.refresh_group_proofs
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @ready(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @opaque_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @opaque_group} {
    %one = llvm.mlir.constant(1 : i8) : i8
    %bits = llvm.mlir.constant(1 : i64) : i64
    %address = llvm.inttoptr %bits : i64 to !llvm.ptr
    llvm.store %one, %address : i8, !llvm.ptr
    llvm.return
  }
  llvm.func @opaque_group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    llvm.return
  }
}

// -----

// A cyclic body has no finite sweep in either form: the group stays as it was.
// CHECK-LABEL: llvm.func @cyclic_group()
// CHECK-NOT: control_flow_dataflow
// CHECK: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @ready(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @cyclic_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @cyclic_group} {
    %base = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    llvm.br ^body
  ^body:
    %value = llvm.load %base : !llvm.ptr -> i8
    %again = llvm.trunc %value : i8 to i1
    llvm.cond_br %again, ^body, ^done
  ^done:
    llvm.return
  }
  llvm.func @cyclic_group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    llvm.return
  }
}
