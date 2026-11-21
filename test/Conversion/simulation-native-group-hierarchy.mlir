// RUN: talos-opt %s --talos-materialize-native-eval-groups -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=CFG < %t.mlir
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 1 : i64}"' --talos-materialize-native-eval-groups | FileCheck %s --check-prefix=BUDGET --implicit-check-not=group_children --implicit-check-not=dataflow_executor --implicit-check-not=dataflow_candidate

// Runtime behavior is checked in ../Runtime/simulation-native-group-hierarchy.test.

// A boundary in the middle refines only its child. Its volatile access does
// not fit the control-flow form. Pure siblings keep their members' CFG and
// select their own domain. Source owner identities and backward work survive
// the two-level hierarchy; an inactive child holds deposited state.
// The slow counters distinguish the selected paths, independently of values.
//
// CHECK-LABEL: llvm.func @group()
// CHECK-SAME: schedule.eval.group_children = [@group.child0, @group.child2]
// CHECK-DAG: schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
// CHECK-DAG: llvm.cond_br
// CHECK-DAG: llvm.call @group.child0.dataflow()
// CHECK-DAG: llvm.call @group.child0()
// CHECK-DAG: llvm.call @group.child2()
// CHECK: llvm.return
// CHECK-DAG: llvm.func @group.child0() attributes {{.*}}schedule.eval.dataflow_executor = @group.child0.dataflow
// CHECK-DAG: llvm.func @group.child2() attributes {{.*}}schedule.eval.group_children = [@group.child2.child0, @group.child2.child1]
// CHECK-DAG: llvm.func @group.child2.child1() attributes {{.*}}schedule.eval.dataflow_executor = @group.child2.child1.dataflow
// CHECK-DAG: llvm.func @group.child0.dataflow() attributes {{.*}}schedule.eval.control_flow_dataflow
// CHECK-DAG: llvm.func @group.child2.child1.dataflow() attributes {{.*}}schedule.eval.control_flow_dataflow
// Each member of the pure sibling keeps its activation test and runs its
// consume and update only on its own taken arm.
// CFG-LABEL: llvm.func @group.child0.dataflow()
// CFG-SAME: schedule.eval.ranked_members = array<i32: 0, 3>
// CFG: schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
// CFG: llvm.cond_br %{{.*}}, ^[[RUN0:bb[0-9]+]], ^[[CHECK3:bb[0-9]+]]
// CFG: ^[[RUN0]]:
// CFG: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
// CFG: schedule.state.store %{{.*}}, @__talos_state_value[0]
// CFG: llvm.br ^[[CHECK3]]
// CFG: ^[[CHECK3]]:
// CFG-NEXT: schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 3 : i32}
// CFG: llvm.cond_br %{{.*}}, ^[[RUN3:bb[0-9]+]], ^[[DONE:bb[0-9]+]]
// CFG: ^[[RUN3]]:
// CFG: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
// CFG: schedule.state.store %{{.*}}, @__talos_state_value[1]
// CFG: llvm.br ^[[DONE]]
// CFG: ^[[DONE]]:
// CFG-NEXT: llvm.return
// BUDGET: llvm.func @group()

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<3xi8>) : !llvm.array<3 x i8>
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<15> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<2> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @slow0(0 : i32) : i32
  llvm.mlir.global internal @slow2(0 : i32) : i32
  llvm.mlir.global internal @observed(0 : i32) : i32
  llvm.mlir.global internal @disturb(false) : i1
  llvm.func @leaf0() {
    %counter = llvm.mlir.addressof @slow0 : !llvm.ptr
    %old_count = llvm.load %counter : !llvm.ptr -> i32
    %one32 = llvm.mlir.constant(1 : i32) : i32
    %count = llvm.add %old_count, %one32 : i32
    llvm.store %count, %counter : i32, !llvm.ptr
    %old = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one = llvm.mlir.constant(1 : i8) : i8
    %value = llvm.add %old, %one : i8
    schedule.state.store %value, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @leaf2() {
    %counter = llvm.mlir.addressof @slow2 : !llvm.ptr
    %old_count = llvm.load %counter : !llvm.ptr -> i32
    %one32 = llvm.mlir.constant(1 : i32) : i32
    %count = llvm.add %old_count, %one32 : i32
    llvm.store %count, %counter : i32, !llvm.ptr
    %old = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one = llvm.mlir.constant(1 : i8) : i8
    %value = llvm.add %old, %one : i8
    schedule.state.store %value, @__talos_state_value[2] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @boundary() {
    %counter = llvm.mlir.addressof @observed : !llvm.ptr
    %old = llvm.load %counter : !llvm.ptr -> i32
    %one = llvm.mlir.constant(1 : i32) : i32
    %count = llvm.add %old, %one : i32
    llvm.store %count, %counter : i32, !llvm.ptr
    %pending = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %bit0 = llvm.mlir.constant(1 : i64) : i64
    %again = llvm.or %pending, %bit0 : i64
    schedule.ready.word.store %again, @__talos_aot_model_ingress_v1[0]
    %flag = llvm.mlir.addressof @disturb : !llvm.ptr
    %enabled = llvm.load %flag : !llvm.ptr -> i1
    llvm.cond_br %enabled, ^mutate, ^done
  ^mutate:
    %proof = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1 : !llvm.ptr
    %bit2 = llvm.mlir.constant(4 : i64) : i64
    llvm.store %bit2, %proof : i64, !llvm.ptr
    %forward = llvm.or %again, %bit2 : i64
    schedule.ready.word.store %forward, @__talos_aot_model_ingress_v1[0]
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 3, 1, 2>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %pending0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    %bit0 = llvm.mlir.constant(1 : i64) : i64
    %clear0 = llvm.mlir.constant(-2 : i64) : i64
    %selected0 = llvm.and %pending0, %bit0 : i64
    %active0 = llvm.icmp "ne" %selected0, %zero : i64
    llvm.cond_br %active0, ^execute0, ^check3
  ^execute0:
    %remaining0 = llvm.and %pending0, %clear0 : i64
    schedule.ready.word.store %remaining0, @__talos_aot_model_ingress_v1[0]
    llvm.call @leaf0() : () -> ()
    llvm.br ^check3
  ^check3:
    %pending3 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 3 : i32}
    %bit3 = llvm.mlir.constant(8 : i64) : i64
    %clear3 = llvm.mlir.constant(-9 : i64) : i64
    %selected3 = llvm.and %pending3, %bit3 : i64
    %active3 = llvm.icmp "ne" %selected3, %zero : i64
    llvm.cond_br %active3, ^execute3, ^check1
  ^execute3:
    %remaining3 = llvm.and %pending3, %clear3 : i64
    schedule.ready.word.store %remaining3, @__talos_aot_model_ingress_v1[0]
    %old3 = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one3 = llvm.mlir.constant(1 : i8) : i8
    %value3 = llvm.add %old3, %one3 : i8
    schedule.state.store %value3, @__talos_state_value[1] {alignment = 1 : i64} : i8
    llvm.br ^check1
  ^check1:
    %pending1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    %bit1 = llvm.mlir.constant(2 : i64) : i64
    %clear1 = llvm.mlir.constant(-3 : i64) : i64
    %selected1 = llvm.and %pending1, %bit1 : i64
    %active1 = llvm.icmp "ne" %selected1, %zero : i64
    llvm.cond_br %active1, ^execute1, ^check2
  ^execute1:
    %remaining1 = llvm.and %pending1, %clear1 : i64
    schedule.ready.word.store %remaining1, @__talos_aot_model_ingress_v1[0]
    %order1 = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered1 = llvm.load volatile %order1 : !llvm.ptr -> i32
    llvm.call @boundary() : () -> ()
    llvm.br ^check2
  ^check2:
    %pending2 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 2 : i32}
    %bit2 = llvm.mlir.constant(4 : i64) : i64
    %clear2 = llvm.mlir.constant(-5 : i64) : i64
    %selected2 = llvm.and %pending2, %bit2 : i64
    %active2 = llvm.icmp "ne" %selected2, %zero : i64
    llvm.cond_br %active2, ^execute2, ^done
  ^execute2:
    %remaining2 = llvm.and %pending2, %clear2 : i64
    schedule.ready.word.store %remaining2, @__talos_aot_model_ingress_v1[0]
    llvm.call @leaf2() : () -> ()
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 3, 1, 2>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @group} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %pending0 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    %bit0 = llvm.mlir.constant(1 : i64) : i64
    %clear0 = llvm.mlir.constant(-2 : i64) : i64
    %selected0 = llvm.and %pending0, %bit0 : i64
    %active0 = llvm.icmp "ne" %selected0, %zero : i64
    llvm.cond_br %active0, ^execute0, ^check3
  ^execute0:
    %remaining0 = llvm.and %pending0, %clear0 : i64
    schedule.ready.word.store %remaining0, @__talos_aot_model_ingress_v1[0]
    %old0 = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one0 = llvm.mlir.constant(1 : i8) : i8
    %value0 = llvm.add %old0, %one0 : i8
    schedule.state.store %value0, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.br ^check3
  ^check3:
    %pending3 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 3 : i32}
    %bit3 = llvm.mlir.constant(8 : i64) : i64
    %clear3 = llvm.mlir.constant(-9 : i64) : i64
    %selected3 = llvm.and %pending3, %bit3 : i64
    %active3 = llvm.icmp "ne" %selected3, %zero : i64
    llvm.cond_br %active3, ^execute3, ^check1
  ^execute3:
    %remaining3 = llvm.and %pending3, %clear3 : i64
    schedule.ready.word.store %remaining3, @__talos_aot_model_ingress_v1[0]
    %old3 = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one3 = llvm.mlir.constant(1 : i8) : i8
    %value3 = llvm.add %old3, %one3 : i8
    schedule.state.store %value3, @__talos_state_value[1] {alignment = 1 : i64} : i8
    llvm.br ^check1
  ^check1:
    %pending1 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    %bit1 = llvm.mlir.constant(2 : i64) : i64
    %clear1 = llvm.mlir.constant(-3 : i64) : i64
    %selected1 = llvm.and %pending1, %bit1 : i64
    %active1 = llvm.icmp "ne" %selected1, %zero : i64
    llvm.cond_br %active1, ^execute1, ^check2
  ^execute1:
    %remaining1 = llvm.and %pending1, %clear1 : i64
    schedule.ready.word.store %remaining1, @__talos_aot_model_ingress_v1[0]
    %order1 = llvm.mlir.addressof @observed : !llvm.ptr
    %ordered1 = llvm.load volatile %order1 : !llvm.ptr -> i32
    llvm.call @boundary() : () -> ()
    llvm.br ^check2
  ^check2:
    %pending2 = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 2 : i32}
    %bit2 = llvm.mlir.constant(4 : i64) : i64
    %clear2 = llvm.mlir.constant(-5 : i64) : i64
    %selected2 = llvm.and %pending2, %bit2 : i64
    %active2 = llvm.icmp "ne" %selected2, %zero : i64
    llvm.cond_br %active2, ^execute2, ^done
  ^execute2:
    %remaining2 = llvm.and %pending2, %clear2 : i64
    schedule.ready.word.store %remaining2, @__talos_aot_model_ingress_v1[0]
    %old2 = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one2 = llvm.mlir.constant(1 : i8) : i8
    %value2 = llvm.add %old2, %one2 : i8
    schedule.state.store %value2, @__talos_state_value[2] {alignment = 1 : i64} : i8
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @main() -> i32 {
    %proof = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1 : !llvm.ptr
    %slow0 = llvm.mlir.addressof @slow0 : !llvm.ptr
    %slow2 = llvm.mlir.addressof @slow2 : !llvm.ptr
    %observed = llvm.mlir.addressof @observed : !llvm.ptr
    %disturb = llvm.mlir.addressof @disturb : !llvm.ptr
    %yes = llvm.mlir.constant(true) : i1
    %no = llvm.mlir.constant(false) : i1
    %zero = llvm.mlir.constant(0 : i32) : i32
    %one = llvm.mlir.constant(1 : i32) : i32
    %two = llvm.mlir.constant(2 : i32) : i32
    %zero64 = llvm.mlir.constant(0 : i64) : i64
    %one64 = llvm.mlir.constant(1 : i64) : i64
    %two64 = llvm.mlir.constant(2 : i64) : i64
    %four64 = llvm.mlir.constant(4 : i64) : i64
    %outside = llvm.mlir.constant(128 : i64) : i64
    %two8 = llvm.mlir.constant(2 : i8) : i8
    %three8 = llvm.mlir.constant(3 : i8) : i8
    %four8 = llvm.mlir.constant(4 : i8) : i8
    llvm.call @group() : () -> ()
    %result = schedule.state.load @__talos_state_value[2] {alignment = 1 : i64} : i8
    %backward = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %c0 = llvm.load %slow0 : !llvm.ptr -> i32
    %c2 = llvm.load %slow2 : !llvm.ptr -> i32
    %bc = llvm.load %observed : !llvm.ptr -> i32
    %v = llvm.icmp "eq" %result, %two8 : i8
    %b = llvm.icmp "eq" %backward, %one64 : i64
    %p0 = llvm.icmp "eq" %c0, %zero : i32
    %p2 = llvm.icmp "eq" %c2, %zero : i32
    %pb = llvm.icmp "eq" %bc, %one : i32
    %a = llvm.and %v, %b : i1
    %c = llvm.and %p0, %p2 : i1
    %d = llvm.and %a, %c : i1
    %visible_middle = schedule.state.load @__talos_state_value[1] {alignment = 1 : i64} : i8
    %forwarded = llvm.icmp "eq" %visible_middle, %two8 : i8
    %executed = llvm.and %d, %pb : i1
    %first = llvm.and %executed, %forwarded : i1
    llvm.call @group() : () -> ()
    %held = schedule.state.load @__talos_state_value[2] {alignment = 1 : i64} : i8
    %drained = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %h = llvm.icmp "eq" %held, %two8 : i8
    %r = llvm.icmp "eq" %drained, %zero64 : i64
    %second = llvm.and %h, %r : i1
    // Only the boundary actor is initially pending. Its callback publishes
    // the consumer and invalidates its proof before that consumer executes.
    llvm.store %yes, %disturb : i1, !llvm.ptr
    schedule.ready.word.store %two64, @__talos_aot_model_ingress_v1[0]
    llvm.call @group() : () -> ()
    %fallback = llvm.load %slow2 : !llvm.ptr -> i32
    %updated = schedule.state.load @__talos_state_value[2] {alignment = 1 : i64} : i8
    %f = llvm.icmp "eq" %fallback, %one : i32
    %u = llvm.icmp "eq" %updated, %three8 : i8
    %third = llvm.and %f, %u : i1
    llvm.store %no, %disturb : i1, !llvm.ptr
    // Drain the backward publication before starting another activation.
    llvm.call @group() : () -> ()
    llvm.store %outside, %proof : i64, !llvm.ptr
    schedule.ready.word.store %four64, @__talos_aot_model_ingress_v1[0]
    llvm.call @group() : () -> ()
    %resumed = llvm.load %slow2 : !llvm.ptr -> i32
    %no_replay = llvm.load %observed : !llvm.ptr -> i32
    %s = llvm.icmp "eq" %resumed, %one : i32
    %n = llvm.icmp "eq" %no_replay, %two : i32
    %last_output = schedule.state.load @__talos_state_value[2] {alignment = 1 : i64} : i8
    %last = llvm.icmp "eq" %last_output, %four8 : i8
    %not_replayed = llvm.and %s, %n : i1
    %fourth = llvm.and %not_replayed, %last : i1
    %left = llvm.and %first, %second : i1
    %right = llvm.and %third, %fourth : i1
    %ok = llvm.and %left, %right : i1
    %exit = llvm.select %ok, %zero, %one : i1, i32
    llvm.return %exit : i32
  }
}
