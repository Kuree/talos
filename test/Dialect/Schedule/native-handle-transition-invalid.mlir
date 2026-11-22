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

// -----

llvm.func @no_value_bits(%context: !llvm.ptr, %handle: i64, %value: i0) {
  // expected-error @below {{publishes no bits}}
  schedule.transition.handle %context, %handle from %value to %value : i0
  llvm.return
}

// -----

llvm.func @value_fact(%context: !llvm.ptr, %handle: i64, %value: i72) {
  // expected-error @below {{carries the schedule fact 'schedule.eval.source_owner' as a property, not an attribute}}
  schedule.transition.handle %context, %handle from %value to %value {schedule.eval.source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>} : i72
  llvm.return
}

// -----

llvm.mlir.global internal @value_outside() : i72 {
  %null = llvm.mlir.zero : !llvm.ptr
  %handle = llvm.mlir.constant(0 : i64) : i64
  %value = llvm.mlir.constant(0 : i72) : i72
  // expected-error @below {{must be in a function}}
  schedule.transition.handle %null, %handle from %value to %value : i72
  llvm.return %value : i72
}

// -----

// The value form's planes are as wide as its store; its custom syntax infers
// them from one type, so these use the generic form.
llvm.func @new_type(%context: !llvm.ptr, %handle: i64, %old: i72, %new: i71) {
  // expected-error @below {{the new value has the old value's type}}
  "schedule.transition.handle"(%context, %handle, %old, %new) <{operandSegmentSizes = array<i32: 1, 1, 1, 0, 1, 0>}> : (!llvm.ptr, i64, i72, i71) -> ()
  llvm.return
}

// -----

llvm.func @old_unknown_type(%context: !llvm.ptr, %handle: i64, %value: i72, %unknown: i71) {
  // expected-error @below {{the old X/Z bits have the value's type}}
  "schedule.transition.handle"(%context, %handle, %value, %unknown, %value) <{operandSegmentSizes = array<i32: 1, 1, 1, 1, 1, 0>}> : (!llvm.ptr, i64, i72, i71, i72) -> ()
  llvm.return
}

// -----

llvm.func @new_unknown_type(%context: !llvm.ptr, %handle: i64, %value: i72, %unknown: i71) {
  // expected-error @below {{the new X/Z bits have the value's type}}
  "schedule.transition.handle"(%context, %handle, %value, %value, %unknown) <{operandSegmentSizes = array<i32: 1, 1, 1, 0, 1, 1>}> : (!llvm.ptr, i64, i72, i72, i71) -> ()
  llvm.return
}

// -----

llvm.func @value_owner(%context: !llvm.ptr, %handle: i64, %value: i72) {
  // expected-error @below {{requires a canonical code-unit/continuation owner}}
  schedule.transition.handle %context, %handle from %value to %value {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 4294967296 : i64>} : i72
  llvm.return
}
