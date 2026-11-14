// RUN: talos-opt %s --inline | FileCheck %s

// Typed state accesses are plain memory accesses: a body holding them
// inlines like one holding LLVM loads and stores.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @use(!llvm.ptr)
  llvm.func @member(%v: i8) -> i8 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    schedule.state.store %v, @__talos_state_value[2] {alignment = 1 : i64} : i8
    %x = schedule.state.load @__talos_state_value[3] {alignment = 1 : i64} : i8
    llvm.return %x : i8
  }
  // CHECK-LABEL: llvm.func @group(
  // CHECK-NOT: llvm.call @member
  // CHECK: schedule.state.address @__talos_state_value
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_value[2]
  // CHECK: schedule.state.load @__talos_state_value[3]
  llvm.func @group(%v: i8) -> i8 {
    %x = llvm.call @member(%v) : (i8) -> i8
    llvm.return %x : i8
  }
}
