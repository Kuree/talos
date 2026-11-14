// RUN: talos-opt %s --finalize-native-llvm | FileCheck %s

// The composite finalization raises state accesses to typed schedule
// operations and lowers them again, so it loads the schedule dialect even
// for input that has none.
// CHECK-LABEL: llvm.func @f()
// CHECK: %[[PLANE:.*]] = llvm.mlir.addressof @__talos_state_value
// CHECK-NEXT: %[[ADDRESS:.*]] = llvm.getelementptr %[[PLANE]][4]
// CHECK-NEXT: llvm.load %[[ADDRESS]] {alignment = 1 : i64} : !llvm.ptr -> i8
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @f() -> i8 {
    %a = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %p = llvm.getelementptr %a[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %x = llvm.load %p {alignment = 1 : i64} : !llvm.ptr -> i8
    llvm.return %x : i8
  }
}
