// RUN: talos-opt %s --split-input-file --test-talos-lower-startup-lifecycle --verify-diagnostics -o /dev/null

// Startup lifecycle lowering fails closed when the module lacks what the
// generated scheduler main provides, or when its descriptor and state planes
// disagree.

// expected-error @+1 {{the startup lifecycle requires a generated scheduler main}}
module attributes {native.startup_state_sync} {
}

// -----

// expected-error @+1 {{the startup lifecycle requires the current context global @__talos_current_context}}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 64 state_sync
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// expected-error @+1 {{the startup lifecycle requires the native state value plane @__talos_state_value}}
module attributes {native.startup_vpi} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 0 vpi
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// The driver asked for state synchronization, but main has no start.
// expected-error @+1 {{generated scheduler lifecycle is incomplete}}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @main() -> i32 {
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// VPI needs exactly one finish and one shutdown.
// expected-error @+1 {{generated scheduler lifecycle is incomplete}}
module attributes {native.startup_vpi} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @main(%context: !llvm.ptr, %status: i32) -> i32 {
    schedule.lifecycle.start state_bits 64 vpi
    %final = schedule.lifecycle.finish %context, %status : (!llvm.ptr, i32) -> i32
    llvm.return %final : i32
  }
}

// -----

// expected-error @+1 {{generated native state planes disagree}}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<4xi8>) : !llvm.array<4 x i8>
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 32 state_sync
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// expected-error @+1 {{generated native state planes disagree}}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(0 : i64) : i64
  llvm.mlir.global internal @__talos_state_unknown(0 : i64) : i64
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 64 state_sync
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// Eight plane bytes hold at most 64 state bits (64 lowers; see
// simulation-startup-lifecycle-sync.mlir).
// expected-error @+1 {{execution descriptor disagrees with generated native state planes}}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 65 state_sync
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// Only a two-state executable may lack the unknown plane.
// expected-error @+1 {{four-state execution requires an unknown plane}}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 64 state_sync
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}
