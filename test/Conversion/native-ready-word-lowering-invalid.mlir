// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-ready-words))' --verify-diagnostics

// Before lowering, a function accesses a ready set only through ready actions
// and typed words, which the native passes before it inspect; an LLVM address
// of the set would hide accesses from them.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @raw() -> i64 {
    // expected-error @+1 {{takes a ready set's address outside typed ready operations}}
    %set = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
    %word = llvm.load %set : !llvm.ptr -> i64
    llvm.return %word : i64
  }
}
