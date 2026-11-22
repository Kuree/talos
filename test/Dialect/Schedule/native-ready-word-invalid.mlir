// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  llvm.mlir.global internal @pending(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{names 'pending', no generated ready set}}
    %word = schedule.ready.word.load @pending[0]
    llvm.return %word : i64
  }
}

// -----
module {
  llvm.func @bad(%bits: i64) {
    // expected-error @+1 {{must reference the llvm.mlir.global of its ready set, an array of i64 words}}
    schedule.ready.word.store %bits, @__talos_aot_model_ingress_v1[0]
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%word: i64) -> i64 {
    // expected-error @+1 {{accesses word 2 of a ready set of 2 words}}
    %bits = schedule.ready.word.load @__talos_aot_model_ingress_v1[%word + 2]
    llvm.return %bits : i64
  }
}

// -----
// A static word is unsigned: -1 names word 2^64 - 1, past the end of any
// set, not the word before it.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{accesses word 18446744073709551615 of a ready set of 2 words}}
    %word = schedule.ready.word.load @__talos_aot_model_ingress_v1[-1]
    llvm.return %word : i64
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%bits: i64) {
    // expected-error @+1 {{accesses word 18446744073709551615 of a ready set of 2 words}}
    schedule.ready.word.store %bits, @__talos_aot_model_ingress_v1[-1]
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{carries the schedule fact 'schedule.eval.activation_entry' as a property, not an attribute}}
    %bits = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {schedule.eval.activation_entry = 0 : i32}
    llvm.return %bits : i64
  }
}

// -----
// A global's initializer accesses no ready set word.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @outside() : i64 {
    // expected-error @below {{must be in a function}}
    %bits = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    llvm.return %bits : i64
  }
}
