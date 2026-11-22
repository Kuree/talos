// RUN: talos-opt %s --split-input-file --verify-diagnostics

llvm.func @no_bits(%context: !llvm.ptr, %handle: i64, %snapshot: !llvm.ptr) {
  // expected-error @below {{publishes no bits}}
  schedule.transition.handle_bytes %context, %handle from %snapshot to %snapshot {width = 0 : i64}
  llvm.return
}

// -----

llvm.func @owner(%context: !llvm.ptr, %handle: i64, %snapshot: !llvm.ptr) {
  // expected-error @below {{requires a canonical code-unit/continuation owner}}
  schedule.transition.handle_bytes %context, %handle from %snapshot to %snapshot {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 4294967296 : i64>, width = 72 : i64}
  llvm.return
}

// -----

llvm.func @fact(%context: !llvm.ptr, %handle: i64, %snapshot: !llvm.ptr) {
  // expected-error @below {{carries the schedule fact 'schedule.eval.nba_equivalent_store' as a property, not an attribute}}
  schedule.transition.handle_bytes %context, %handle from %snapshot to %snapshot {schedule.eval.nba_equivalent_store, width = 72 : i64}
  llvm.return
}

// -----

llvm.mlir.global internal @outside() : !llvm.ptr {
  %null = llvm.mlir.zero : !llvm.ptr
  %handle = llvm.mlir.constant(0 : i64) : i64
  // expected-error @below {{must be in a function}}
  schedule.transition.handle_bytes %null, %handle from %null to %null {width = 72 : i64}
  llvm.return %null : !llvm.ptr
}
