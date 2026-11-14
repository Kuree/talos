// RUN: talos-opt %s --split-input-file --verify-diagnostics --pass-pipeline='builtin.module(llvm.func(lower-native-state-access))'

// Native passes before the lowering see a state plane only through typed
// state operations, so the lowering rejects any other access to one.

module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @plain_address() -> i8 {
    // expected-error @below {{takes a state plane's address outside typed state operations}}
    %a = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %x = llvm.load %a {alignment = 1 : i64} : !llvm.ptr -> i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @base_gep() -> i8 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    // expected-error @below {{accesses a state plane through its address instead of a typed state access}}
    %p = llvm.getelementptr %a[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %x = llvm.load %p {alignment = 1 : i64} : !llvm.ptr -> i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @window_store(%v: i8, %d: i64) {
    %w = schedule.state.window_address @__talos_state_unknown[%d + 2] : !llvm.ptr
    // expected-error @below {{accesses a state plane through its address instead of a typed state access}}
    llvm.store %v, %w {alignment = 1 : i64} : i8, !llvm.ptr
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @base_load() -> i8 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    // expected-error @below {{accesses a state plane through its address instead of a typed state access}}
    %x = llvm.load %a {alignment = 1 : i64} : !llvm.ptr -> i8
    llvm.return %x : i8
  }
}

// -----

// A select would hide the address's origin from the native passes.
module {
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @select_window(%c: i1, %local: !llvm.ptr) {
    %a = schedule.state.window_address @__talos_state_unknown[2] : !llvm.ptr
    %b = schedule.state.window_address @__talos_state_unknown[4] : !llvm.ptr
    // expected-error @below {{accesses a state plane through its address instead of a typed state access}}
    %p = llvm.select %c, %a, %b : i1, !llvm.ptr
    %n = llvm.mlir.constant(2 : i64) : i64
    "llvm.intr.memcpy"(%p, %local, %n) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @atomic(%v: i8) -> i8 {
    %w = schedule.state.window_address @__talos_state_value[3] : !llvm.ptr
    // expected-error @below {{accesses a state plane through its address instead of a typed state access}}
    %old = llvm.atomicrmw add %w, %v seq_cst : !llvm.ptr, i8
    llvm.return %old : i8
  }
}

// -----

// A window address may leave typed operations whole: as a copy's operand or
// a call's argument.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @use(!llvm.ptr)
  llvm.func @escapes(%local: !llvm.ptr) {
    %w = schedule.state.window_address @__talos_state_value[4] : !llvm.ptr
    %n = llvm.mlir.constant(8 : i64) : i64
    "llvm.intr.memcpy"(%local, %w, %n) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.call @use(%w) : (!llvm.ptr) -> ()
    llvm.return
  }
}
