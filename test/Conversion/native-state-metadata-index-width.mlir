// RUN: talos-opt %s --address-native-state-through-bases | FileCheck %s
// RUN: talos-opt %s --address-native-state-through-bases | talos-translate --mlir-to-llvmir | %llvm_dist/bin/opt -passes=verify -disable-output

// The GEP index width may be smaller than both the pointer and its integer
// operand. 128 fits this allocation but wraps to -128 in an 8-bit GEP index.
// No bounded-state alias scope may be inferred from its original i64 value.
module attributes {llvm.data_layout = "e-p:64:64:64:8"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<256xi8>) : !llvm.array<256 x i8>
  llvm.func @metadata_only() attributes {schedule.eval.state_metadata_only}
  // CHECK-LABEL: llvm.func @wrapped_index
  // CHECK-NOT: alias_scopes
  // CHECK: llvm.call @metadata_only()
  // CHECK-NOT: alias_scopes
  // CHECK: llvm.return
  llvm.func @wrapped_index() -> i8 {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %offset = llvm.mlir.constant(128 : i64) : i64
    %p = llvm.getelementptr %vp[%offset] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %before = llvm.load %p : !llvm.ptr -> i8
    llvm.call @metadata_only() : () -> ()
    %after = llvm.load %p : !llvm.ptr -> i8
    %sum = llvm.add %before, %after : i8
    llvm.return %sum : i8
  }

  // Other address spaces can have different pointer/index contracts.
  // CHECK-LABEL: llvm.func @other_address_space
  // CHECK-NOT: alias_scopes
  // CHECK: llvm.return
  llvm.func @other_address_space() -> i8 {
    %vp = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %other = llvm.addrspacecast %vp : !llvm.ptr to !llvm.ptr<1>
    %value = llvm.load %other : !llvm.ptr<1> -> i8
    llvm.call @metadata_only() : () -> ()
    llvm.return %value : i8
  }
}
