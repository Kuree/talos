// RUN: talos-opt %s --split-input-file --verify-diagnostics

// -----
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<2 x i64>
  llvm.func @invalid(%source: !llvm.ptr) {
    // expected-error@+1 {{ready capacity must be between 1 and UINT32_MAX}}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 0 : i64}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<2 x i64>
  llvm.func @invalid(%source: !llvm.ptr) {
    // expected-error@+1 {{ready capacity must be between 1 and UINT32_MAX}}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = -1 : i64}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<2 x i64>
  llvm.func @invalid(%source: !llvm.ptr) {
    // expected-error@+1 {{ready capacity must be between 1 and UINT32_MAX}}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 4294967296 : i64}
    llvm.return
  }
}
