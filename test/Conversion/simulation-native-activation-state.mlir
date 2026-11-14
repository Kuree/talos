// RUN: talos-opt %s --talos-materialize-native-eval-groups -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos-opt %s --mlir-disable-threading --talos-materialize-native-eval-groups -o %t.serial
// RUN: diff %t.mlir %t.serial
// Runtime checks are in ../Runtime/simulation-native-activation-state.test.
// A shared output is local to one activation between observation boundaries.
// Keep both planes and CFG loops; preserve each captured transition, including
// a transient 0 -> 1 -> 0, even though canonical storage only flushes at exit.
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<1xi8>) : !llvm.array<1 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<1xi8>) : !llvm.array<1 x i8>
  llvm.mlir.global internal @transitions(0 : i8) : i8
  // CHECK-LABEL: llvm.func @activation
  // CHECK-SAME: schedule.eval.ssa_unknown_ranges = 1 : i64
  // CHECK-SAME: schedule.eval.ssa_value_ranges = 1 : i64
  // CHECK: schedule.state.load
  // CHECK: schedule.state.load
  // CHECK: llvm.br
  // CHECK: llvm.cond_br
  // CHECK-NOT: {{llvm.load|llvm.store|schedule.state.load|schedule.state.store}}
  // CHECK: llvm.br
  // CHECK: schedule.state.store
  // CHECK: llvm.return
  llvm.func @activation(%count: i8) attributes {schedule.eval.raw_captures} {
    %t = llvm.mlir.addressof @transitions : !llvm.ptr
    %zero = llvm.mlir.constant(0 : i8) : i8
    %one = llvm.mlir.constant(1 : i8) : i8
    %all = llvm.mlir.constant(-1 : i8) : i8
    schedule.state.store %zero, @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.state.store %zero, @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    llvm.br ^header(%zero, %zero : i8, i8)
  ^header(%i: i8, %seen: i8):
    %more = llvm.icmp "ult" %i, %count : i8
    llvm.cond_br %more, ^body, ^exit
  ^body:
    %oldv = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %oldx = schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %newv = llvm.xor %oldv, %one : i8
    %newx = llvm.xor %oldx, %all : i8
    schedule.state.store %newv, @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.state.store %newx, @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %delta = llvm.xor %newv, %oldv : i8
    %observed = llvm.or %seen, %delta : i8
    %next = llvm.add %i, %one : i8
    llvm.br ^header(%next, %observed : i8, i8)
  ^exit:
    llvm.store %seen, %t : i8, !llvm.ptr
    llvm.return
  }
  // A separate reader observes the final canonical planes.
  llvm.func @main() -> i32 {
    %two = llvm.mlir.constant(2 : i8) : i8
    llvm.call @activation(%two) : (i8) -> ()
    %t = llvm.mlir.addressof @transitions : !llvm.ptr
    %value = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %unknown = schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %seen = llvm.load %t : !llvm.ptr -> i8
    %zero = llvm.mlir.constant(0 : i8) : i8
    %one = llvm.mlir.constant(1 : i8) : i8
    %vok = llvm.icmp "eq" %value, %zero : i8
    %xok = llvm.icmp "eq" %unknown, %zero : i8
    %tok = llvm.icmp "eq" %seen, %one : i8
    %planes = llvm.and %vok, %xok : i1
    %ok = llvm.and %planes, %tok : i1
    %pass = llvm.mlir.constant(0 : i32) : i32
    %fail = llvm.mlir.constant(1 : i32) : i32
    %result = llvm.select %ok, %pass, %fail : i1, i32
    llvm.return %result : i32
  }
}
