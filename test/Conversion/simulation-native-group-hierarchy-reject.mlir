// RUN: talos-opt %s --talos-materialize-native-eval-groups -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=group_children --implicit-check-not=group_parent --implicit-check-not=dataflow_executor --implicit-check-not=dataflow_candidate --implicit-check-not=control_flow_dataflow < %t.mlir

// An unsuccessful refinement must retain the exact original executor. Entry
// metadata is not a license to bypass effects, replay a captured load, or
// invent an owner. Even pure, speculatable freeze cannot be replayed: its
// captured choice must remain correlated across children. An entry is a
// typed load of the member's ingress word; the tag on an LLVM load
// (raw_entry) certifies nothing. No unused child helpers survive.
// Each candidate has a volatile load beside its call, so group dataflow
// rejects it whole (no control_flow_dataflow) and the hierarchy tries the
// split. Except in all_rejected, the second member has no call or volatile
// access: without its defect, each case would split as
// simulation-native-group-hierarchy does.
// CHECK: llvm.func @foreign()
module attributes {schedule.native.max_inline_ops = 5000 : i64} {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<1xi8>) : !llvm.array<1 x i8>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @observed(0 : i32) : i32
  llvm.func @foreign()
  llvm.func @frozen_capture() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %undefined = llvm.mlir.undef : i8
    %captured = llvm.freeze %undefined : i8
    schedule.state.store %captured, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    schedule.state.store %captured, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @frozen_capture_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @frozen_capture} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %undefined = llvm.mlir.undef : i8
    %captured = llvm.freeze %undefined : i8
    schedule.state.store %captured, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    schedule.state.store %captured, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @all_rejected() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %again = llvm.load volatile %observed : !llvm.ptr -> i32
    llvm.return
  }
  llvm.func @all_rejected_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @all_rejected} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %again = llvm.load volatile %observed : !llvm.ptr -> i32
    llvm.return
  }
  llvm.func @duplicate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @duplicate_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @duplicate} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @missing() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @missing_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @missing} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @wrong_owner() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 2 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @wrong_owner_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @wrong_owner} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 2 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @raw_entry() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %ready = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
    %r1 = llvm.load %ready {schedule.eval.activation_entry = 1 : i32} : !llvm.ptr -> i64
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @raw_entry_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @raw_entry} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %ready = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
    %r1 = llvm.load %ready {schedule.eval.activation_entry = 1 : i32} : !llvm.ptr -> i64
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @prefix_effect() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    llvm.call @foreign() : () -> ()
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @prefix_effect_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @prefix_effect} {
    llvm.call @foreign() : () -> ()
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @bypass() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %zero = llvm.mlir.constant(0 : i64) : i64
    %skip = llvm.icmp "eq" %r0, %zero : i64
    llvm.cond_br %skip, ^done, ^next
  ^next:
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @bypass_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @bypass} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %zero = llvm.mlir.constant(0 : i64) : i64
    %skip = llvm.icmp "eq" %r0, %zero : i64
    llvm.cond_br %skip, ^done, ^next
  ^next:
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    %one = llvm.mlir.constant(1 : i8) : i8
    schedule.state.store %one, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @cross_capture() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %captured = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    schedule.state.store %captured, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @cross_capture_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @cross_capture} {
    %r0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    schedule.ready.word.store %r0, @__talos_aot_model_ingress_v1[0]
    llvm.call @foreign() : () -> ()
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered = llvm.load volatile %observed : !llvm.ptr -> i32
    %captured = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %r1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    schedule.ready.word.store %r1, @__talos_aot_model_ingress_v1[0]
    schedule.state.store %captured, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
}
