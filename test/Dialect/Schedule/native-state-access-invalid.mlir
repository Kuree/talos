// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  llvm.mlir.global internal @other(0 : i8) : i8
  llvm.func @not_a_plane(%v: i8) -> i8 {
    // expected-error @below {{names 'other', no native state plane}}
    %a = schedule.state.address @other : !llvm.ptr
    llvm.return %v : i8
  }
}

// -----

module {
  llvm.mlir.global internal @other(0 : i8) : i8
  llvm.func @load_not_a_plane() -> i8 {
    // expected-error @below {{names 'other', no native state plane}}
    %x = schedule.state.load @other[0] {alignment = 1 : i64} : i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.mlir.global internal @other(0 : i8) : i8
  llvm.func @store_not_a_plane(%v: i8) {
    // expected-error @below {{names 'other', no native state plane}}
    schedule.state.store %v, @other[0] {alignment = 1 : i64} : i8
    llvm.return
  }
}

// -----

// A state access needs its plane's global.
module {
  llvm.func @missing_plane(%offset: i64) -> i8 {
    // expected-error @below {{must reference the llvm.mlir.global of its plane}}
    %x = schedule.state.load @__talos_state_unknown[%offset] {alignment = 1 : i64} : i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.func @__talos_state_value()
  llvm.func @plane_is_function() {
    // expected-error @below {{must reference the llvm.mlir.global of its plane}}
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    llvm.return
  }
}

// -----

// Only functions are lowered to LLVM accesses.
module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.mlir.global internal @pointer() : !llvm.ptr {
    // expected-error @below {{must be in a function}}
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    llvm.return %a : !llvm.ptr
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @bad_alignment() -> i8 {
    // expected-error @below {{attribute 'alignment' failed to satisfy constraint}}
    %x = schedule.state.load @__talos_state_value[0] {alignment = 3 : i64} : i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @not_an_integer() -> f32 {
    // expected-error @below {{result #0 must be}}
    %x = schedule.state.load @__talos_state_value[0] {alignment = 4 : i64} : f32
    llvm.return %x : f32
  }
}

// -----

// What native passes need to know about an access is a property.
module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @discardable_tag() -> i8 {
    // expected-error @below {{carries the schedule fact}}
    %x = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64, schedule.eval.group_owner = 3 : i32} : i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @bad_window(%v: i8, %d: i64) {
    // expected-error @below {{has a malformed window}}
    schedule.state.store %v, @__talos_state_value[%d] {alignment = 1 : i64, window = array<i64: 8, 4>} : i8
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_unknown(0 : i8) : i8
  llvm.func @bad_written_bits(%v: i8, %d: i64) {
    // expected-error @below {{has a malformed written_bits}}
    schedule.state.store %v, @__talos_state_unknown[%d] {alignment = 1 : i64, written_bits = array<i64: 8, 0>} : i8
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @negative_window() -> i8 {
    // expected-error @below {{has a malformed window}}
    %x = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64, window = array<i64: -1, 1>} : i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @wide_owner() -> i8 {
    // expected-error @below {{owner}}
    %x = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64, owner = 3 : i64} : i8
    llvm.return %x : i8
  }
}

// -----

// Other dialects may still annotate an access.
module {
  llvm.mlir.global internal @__talos_state_value(0 : i8) : i8
  llvm.func @foreign_attribute() -> i8 {
    %x = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64, test.tag} : i8
    llvm.return %x : i8
  }
}
