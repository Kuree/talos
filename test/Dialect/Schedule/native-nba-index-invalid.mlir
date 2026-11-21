// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  llvm.mlir.global internal @other(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @not_an_index() -> i64 {
    // expected-error @below {{names 'other', no NBA readiness index}}
    %x = schedule.nba.index.load @other[0]
    llvm.return %x : i64
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @wrong_word() -> i64 {
    // expected-error @below {{accesses word 0, not the word 1 of root 65}}
    %x = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0] {root = 65 : i32}
    llvm.return %x : i64
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @wrong_summary_word(%v: i64) {
    // expected-error @below {{accesses word 0, not the word 1 of root 4096}}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_summary_v1[0] {root = 4096 : i32}
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @canonical_without_root() -> i64 {
    // expected-error @below {{marks a canonical capture without its root}}
    %x = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0] {canonical_capture}
    llvm.return %x : i64
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @capture_on_summary(%v: i64) {
    // expected-error @below {{certifies a capture without marking a generated capture's dirty root}}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_summary_v1[0] {capture = array<i64: 1, 0, 8, 255, 2, 0>, root = 1 : i32}
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @capture_of_another_root(%v: i64) {
    // expected-error @below {{certifies a malformed capture of root 1}}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 2, 0, 8, 255, 2, 0>, root = 1 : i32}
    llvm.return
  }
}

// -----

module {
  llvm.func @no_global() -> i64 {
    // expected-error @below {{must reference the llvm.mlir.global of its index}}
    %x = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0]
    llvm.return %x : i64
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @capture_of_canonical(%v: i64) {
    // expected-error @below {{certifies a capture without marking a generated capture's dirty root}}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {canonical_capture, capture = array<i64: 1, 0, 8, 255, 2, 0>, root = 1 : i32}
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @short_capture(%v: i64) {
    // expected-error @below {{certifies a malformed capture of root 1}}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 1, 0, 8>, root = 1 : i32}
    llvm.return
  }
}

// -----

module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @schedule_tag() -> i64 {
    // expected-error @below {{carries the schedule fact 'schedule.eval.group_owner' as a property, not an attribute}}
    %x = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0] {schedule.eval.group_owner = 1 : i32}
    llvm.return %x : i64
  }
}
