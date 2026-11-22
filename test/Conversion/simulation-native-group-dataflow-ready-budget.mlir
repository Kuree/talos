// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 8 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=FITS
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 7 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=OVER
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 14 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=DYNAMIC-FITS
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 13 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=DYNAMIC-OVER

// The group dataflow budget counts a ready word access as its LLVM form: the
// access, no GEP for word 0, and the set's address once per function. The
// candidate is its two word accesses, the address and five other operations:
// eight fit 8 operations and not 7.
// FITS-LABEL: llvm.func @group()
// FITS-SAME: schedule.eval.control_flow_dataflow
// OVER-LABEL: llvm.func @group()
// OVER-NOT: schedule.eval.control_flow_dataflow
// OVER-SAME: schedule.eval.group_ingress

// A dynamic word access adds an i64 GEP by its index, and a nonzero static
// word a byte GEP after it: `[%word + 1]` counts 3. The candidate's two such
// accesses sit in different blocks, which the lowering gives a GEP each. With
// the set's address, the index's load and address and five other operations,
// it fits 14 operations and not 13.
// DYNAMIC-FITS-LABEL: llvm.func @dynamic()
// DYNAMIC-FITS-SAME: schedule.eval.control_flow_dataflow
// DYNAMIC-OVER-LABEL: llvm.func @dynamic()
// DYNAMIC-OVER-NOT: schedule.eval.control_flow_dataflow
// DYNAMIC-OVER-SAME: schedule.eval.group_ingress
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @slow(0 : i32) : i32
  llvm.mlir.global internal @index(0 : i64) : i64
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %p = llvm.mlir.addressof @slow : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %p : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @group} {
    %pending = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %zero = llvm.mlir.constant(0 : i64) : i64
    %active = llvm.icmp "ne" %pending, %zero : i64
    llvm.cond_br %active, ^run, ^done
  ^run:
    schedule.ready.word.store %zero, @__talos_aot_model_ingress_v1[0]
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @dynamic() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %p = llvm.mlir.addressof @slow : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %p : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @dynamic_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @dynamic} {
    %at = llvm.mlir.addressof @index : !llvm.ptr
    %word = llvm.load %at : !llvm.ptr -> i64
    %pending = schedule.ready.word.load @__talos_aot_model_ingress_v1[%word + 1]
    %zero = llvm.mlir.constant(0 : i64) : i64
    %active = llvm.icmp "ne" %pending, %zero : i64
    llvm.cond_br %active, ^run, ^done
  ^run:
    schedule.ready.word.store %zero, @__talos_aot_model_ingress_v1[%word + 1]
    llvm.br ^done
  ^done:
    llvm.return
  }
}
