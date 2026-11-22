// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  llvm.mlir.global internal @pending(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{names 'pending', no generated ready set}}
    %word = schedule.ready.read @pending[0] {capacity = 64 : i64}
    llvm.return %word : i64
  }
}

// -----
module {
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{must reference the llvm.mlir.global of its ready set, an array of i64 words}}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %mask {capacity = 64 : i64, consume = false}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<2xi32>) : !llvm.array<2 x i32>
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{must reference the llvm.mlir.global of its ready set, an array of i64 words}}
    schedule.ready.commit @__talos_eval_nba_held_wakes_v1[0], %mask, %mask {capacity = 64 : i64}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{accesses word 1 of a ready set of 1 words}}
    schedule.ready.update @__talos_aot_model_ingress_v1[1], %mask {capacity = 128 : i64, consume = true}
    llvm.return
  }
}

// -----
// Capacity 129 has 3 leaves and a dirty level, words 0-3.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%source: !llvm.ptr) {
    // expected-error @+1 {{accesses word 3 of a ready set of 2 words}}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 129 : i64}
    llvm.return
  }
}

// -----
// An add sets its leaf's dirty bits: capacity 128 has leaves 0-1 and its
// dirty level in word 2, which a set of 2 words lacks. A consume touches only
// its leaf (native-ready-set.mlir).
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{accesses word 2 of a ready set of 2 words}}
    schedule.ready.update @__talos_aot_model_ingress_v1[1], %mask {capacity = 128 : i64, consume = false}
    llvm.return
  }
}

// -----
// Capacity 32769 has 513 leaves, a dirty level of 9 words from word 513 and,
// since 9 words exceed the 8 scanned flat, a level of 1 word: word 522.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<522xi64>) : !llvm.array<522 x i64>
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{accesses word 522 of a ready set of 522 words}}
    schedule.ready.update @__talos_aot_model_ingress_v1[512], %mask {capacity = 32769 : i64, consume = false}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{accesses word 2 of a ready set of 2 words}}
    schedule.ready.commit @__talos_eval_nba_held_wakes_v1[0], %mask, %mask {capacity = 128 : i64}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%source: !llvm.ptr) {
    // expected-error @+1 {{accesses word 2 of a ready set of 2 words}}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 128 : i64}
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  llvm.func @bad(%mask: i64) {
    // expected-error @+1 {{ready word must name a leaf within capacity}}
    schedule.ready.commit @__talos_aot_model_ingress_v1[2], %mask, %mask {capacity = 128 : i64}
    llvm.return
  }
}
