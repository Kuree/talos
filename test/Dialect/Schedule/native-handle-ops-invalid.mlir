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

// -----

// The custom syntax infers the operand types, so only the generic form reaches
// the operations' own type constraints.
llvm.func @generic_amount(%handle: i64, %amount: i32) -> i64 {
  // expected-error @below {{'schedule.handle.offset' op operand #1 must be 64-bit signless integer, but got 'i32'}}
  %element = "schedule.handle.offset"(%handle, %amount) : (i64, i32) -> i64
  llvm.return %element : i64
}

// -----

llvm.func @generic_validity(%valid: i64, %handle: i64) -> i64 {
  // expected-error @below {{'schedule.handle.guard' op operand #0 must be 1-bit signless integer, but got 'i64'}}
  %guarded = "schedule.handle.guard"(%valid, %handle) : (i64, i64) -> i64
  llvm.return %guarded : i64
}
