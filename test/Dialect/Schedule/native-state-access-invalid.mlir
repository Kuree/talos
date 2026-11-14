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
