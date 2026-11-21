// RUN: talos-opt %s --split-input-file --verify-diagnostics

// A handle and an offset amount are i64, and a validity is i1.
// expected-note @below {{prior use here}}
llvm.func @narrow_amount(%handle: i64, %amount: i32) -> i64 {
  // expected-error @below {{use of value '%amount' expects different type than prior uses: 'i64' vs 'i32'}}
  %element = schedule.handle.offset %handle, %amount
  llvm.return %element : i64
}

// -----

// expected-note @below {{prior use here}}
llvm.func @wide_validity(%valid: i64, %handle: i64) -> i64 {
  // expected-error @below {{use of value '%valid' expects different type than prior uses: 'i1' vs 'i64'}}
  %guarded = schedule.handle.guard %valid, %handle
  llvm.return %guarded : i64
}
