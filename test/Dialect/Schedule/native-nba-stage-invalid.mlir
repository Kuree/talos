// RUN: talos-opt %s --split-input-file --verify-diagnostics

llvm.func @no_bits(%context: !llvm.ptr, %handle: i64, %value: !llvm.ptr) {
  // expected-error @below {{stages no bits}}
  schedule.nba.stage %context, %handle, %value {root = 0 : i32, site = 1 : i64, state_bits = 64 : i64, width = 0 : i64}
  llvm.return
}

// -----

llvm.func @no_root(%context: !llvm.ptr, %handle: i64, %value: !llvm.ptr) {
  // expected-error @below {{requires attribute 'root'}}
  schedule.nba.stage %context, %handle, %value {site = 1 : i64, state_bits = 64 : i64, width = 8 : i64}
  llvm.return
}

// -----

llvm.mlir.global internal @outside() : !llvm.ptr {
  %null = llvm.mlir.zero : !llvm.ptr
  %handle = llvm.mlir.constant(0 : i64) : i64
  // expected-error @below {{must be in a function}}
  schedule.nba.stage %null, %handle, %null {root = 0 : i32, site = 1 : i64, state_bits = 64 : i64, width = 8 : i64}
  llvm.return %null : !llvm.ptr
}

