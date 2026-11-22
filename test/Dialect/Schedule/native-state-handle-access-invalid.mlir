// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  llvm.mlir.global internal @other(0 : i8) : i8
  llvm.func @not_a_plane(%handle: i64) -> i8 {
    // expected-error @below {{names 'other', no native state plane}}
    %value = schedule.state.load_handle @other[%handle] {state_bits = 8 : i64} : i8
    llvm.return %value : i8
  }
}

// -----

// The runtime keeps the contribution planes behind a handle itself.
module {
  llvm.mlir.global external @__talos_continuous_value() : !llvm.ptr
  llvm.func @contribution(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr) {
    // expected-error @below {{names a contribution plane, which only the runtime accesses through a handle}}
    schedule.state.store_handle_bytes %buffer, @__talos_continuous_value[%handle] changed %changed {state_bits = 8 : i64, width = 8 : i64}
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @no_bits(%handle: i64, %buffer: !llvm.ptr) {
    // expected-error @below {{moves no bits}}
    schedule.state.load_handle_bytes @__talos_state_value[%handle] into %buffer {state_bits = 8 : i64, width = 0 : i64}
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global external @__talos_continuous_unknown() : !llvm.ptr
  llvm.func @scalar_contribution(%handle: i64, %value: i8) {
    // expected-error @below {{names a contribution plane, which only the runtime accesses through a handle}}
    %changed = schedule.state.store_handle %value, @__talos_continuous_unknown[%handle] {state_bits = 8 : i64} : i8
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @scalar_no_bits(%handle: i64, %value: i0) {
    // expected-error @below {{moves no bits}}
    %changed = schedule.state.store_handle %value, @__talos_state_value[%handle] {state_bits = 8 : i64} : i0
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.mlir.global internal @scalar_outside() : i8 {
    %handle = llvm.mlir.constant(0 : i64) : i64
    // expected-error @below {{must be in a function}}
    %value = schedule.state.load_handle @__talos_state_value[%handle] {state_bits = 8 : i64} : i8
    llvm.return %value : i8
  }
}

// -----

module {
  llvm.func @missing_plane(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr) {
    // expected-error @below {{must reference the llvm.mlir.global of its plane}}
    schedule.state.store_handle_bytes %buffer, @__talos_state_unknown[%handle] changed %changed {state_bits = 8 : i64, width = 8 : i64}
    llvm.return
  }
}

// -----

// What native passes need to know about an access is a property.
module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @discardable_tag(%handle: i64, %value: i8) {
    // expected-error @below {{carries the schedule fact}}
    %changed = schedule.state.store_handle %value, @__talos_state_value[%handle] {state_bits = 8 : i64, schedule.eval.group_owner = 3 : i32} : i8
    llvm.return
  }
}

// -----

// Only functions are lowered to runtime calls.
module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.mlir.global internal @outside() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    %handle = llvm.mlir.constant(0 : i64) : i64
    // expected-error @below {{must be in a function}}
    schedule.state.load_handle_bytes @__talos_state_value[%handle] into %null {state_bits = 8 : i64, width = 8 : i64}
    llvm.return %null : !llvm.ptr
  }
}

// -----

// A frame store writes 1 to 64 bits.
module {
  llvm.func @wide_frame(%handle: i64, %value: i65) {
    // expected-error @below {{writes 65 bits, not 1 to 64}}
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64} : i65
    llvm.return
  }
}

// -----

module {
  llvm.func @two_state_unknown(%handle: i64, %value: i8, %unknown: i8) {
    // expected-error @below {{has X/Z bits for a two-state destination}}
    schedule.state.frame_store %value, %unknown to %handle {state_bits = 128 : i64} : i8, i8
    llvm.return
  }
}

// -----

module {
  llvm.func @unknown_width(%handle: i64, %value: i8, %unknown: i4) {
    // expected-error @below {{has X/Z bits of another width than its value}}
    schedule.state.frame_store %value, %unknown to %handle four_state {state_bits = 128 : i64} : i8, i4
    llvm.return
  }
}

// -----

module {
  llvm.func @automatic_no_bits(%context: !llvm.ptr, %handle: i64, %buffer: !llvm.ptr) -> i32 {
    // expected-error @below {{moves no bits}}
    %status = schedule.state.load_automatic %context, %handle into %buffer {width = 0 : i64}
    llvm.return %status : i32
  }
}

// -----

// The reads name canonical planes too.
module {
  llvm.mlir.global external @__talos_continuous_value() : !llvm.ptr
  llvm.func @load_contribution(%handle: i64) -> i8 {
    // expected-error @below {{names a contribution plane, which only the runtime accesses through a handle}}
    %value = schedule.state.load_handle @__talos_continuous_value[%handle] {state_bits = 8 : i64} : i8
    llvm.return %value : i8
  }
}

// -----

module {
  llvm.mlir.global external @__talos_continuous_unknown() : !llvm.ptr
  llvm.func @load_bytes_contribution(%handle: i64, %buffer: !llvm.ptr) {
    // expected-error @below {{names a contribution plane, which only the runtime accesses through a handle}}
    schedule.state.load_handle_bytes @__talos_continuous_unknown[%handle] into %buffer {state_bits = 8 : i64, width = 8 : i64}
    llvm.return
  }
}

// -----

module {
  llvm.func @scalar_missing_plane(%handle: i64) -> i8 {
    // expected-error @below {{must reference the llvm.mlir.global of its plane}}
    %value = schedule.state.load_handle @__talos_state_value[%handle] {state_bits = 8 : i64} : i8
    llvm.return %value : i8
  }
}

// -----

module {
  llvm.func @scalar_store_missing_plane(%handle: i64, %value: i8) {
    // expected-error @below {{must reference the llvm.mlir.global of its plane}}
    %changed = schedule.state.store_handle %value, @__talos_state_unknown[%handle] {state_bits = 8 : i64} : i8
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @frame_outside() : i8 {
    %handle = llvm.mlir.constant(0 : i64) : i64
    %value = llvm.mlir.constant(0 : i8) : i8
    // expected-error @below {{must be in a function}}
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64} : i8
    llvm.return %value : i8
  }
}

// -----

module {
  llvm.func @frame_fact(%handle: i64, %value: i8) {
    // expected-error @below {{carries the schedule fact 'schedule.eval.group_owner' as a property, not an attribute}}
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64, schedule.eval.group_owner = 3 : i32} : i8
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @automatic_outside() : i32 {
    %null = llvm.mlir.zero : !llvm.ptr
    %handle = llvm.mlir.constant(0 : i64) : i64
    // expected-error @below {{must be in a function}}
    %status = schedule.state.load_automatic %null, %handle into %null {width = 8 : i64}
    llvm.return %status : i32
  }
}

// -----

module {
  llvm.func @automatic_fact(%context: !llvm.ptr, %handle: i64, %buffer: !llvm.ptr) -> i32 {
    // expected-error @below {{carries the schedule fact 'schedule.eval.group_owner' as a property, not an attribute}}
    %status = schedule.state.load_automatic %context, %handle into %buffer {width = 8 : i64, schedule.eval.group_owner = 3 : i32}
    llvm.return %status : i32
  }
}
