// RUN: talos-opt %s --split-input-file --verify-diagnostics --pass-pipeline='builtin.module(llvm.func(lower-native-state-access{two-state=true}))'

// Native passes see every access to an accumulator record only as a typed
// field access, so its address flows nowhere else.
module {
  llvm.mlir.global internal @acc(dense<0> : tensor<104xi8>) : !llvm.array<104 x i8>
  llvm.func @use(!llvm.ptr)
  llvm.func @escape() {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    // expected-error @below {{accesses an NBA accumulator record through its address instead of a typed accumulator access}}
    llvm.call @use(%r) : (!llvm.ptr) -> ()
    llvm.return
  }
}

// -----

// A two-state build removes X/Z field accesses before lowering; the
// two-state record has no X/Z field.
module {
  llvm.mlir.global internal @acc(dense<0> : tensor<104xi8>) : !llvm.array<104 x i8>
  llvm.func @unknown() -> i64 {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    // expected-error @below {{accesses the X/Z field of a two-state NBA accumulator record}}
    %x = schedule.nba.acc.load %r[unknown] {alignment = 8 : i64} : i64
    llvm.return %x : i64
  }
}

// -----

module {
  llvm.mlir.global internal @acc(dense<0> : tensor<104xi8>) : !llvm.array<104 x i8>
  llvm.func @integer_escape() -> i64 {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    // expected-error @below {{accesses an NBA accumulator record through its address instead of a typed accumulator access}}
    %i = llvm.ptrtoint %r : !llvm.ptr to i64
    llvm.return %i : i64
  }
}
