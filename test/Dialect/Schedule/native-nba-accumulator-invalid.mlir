// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.func @past_field(%r: !llvm.ptr) -> i32 {
    // expected-error @below {{accesses bytes outside its valid field}}
    %x = schedule.nba.acc.load %r[valid + 4] {alignment = 4 : i64} : i32
    llvm.return %x : i32
  }
}

// -----

module {
  llvm.func @straddles_field(%r: !llvm.ptr, %v: i64) {
    // expected-error @below {{accesses bytes outside its value field}}
    schedule.nba.acc.store %v, %r[value + 28] {alignment = 4 : i64} : i64
    llvm.return
  }
}

// -----

module {
  llvm.func @partial_byte(%r: !llvm.ptr) -> i7 {
    // expected-error @below {{accesses a value of 7 bits, not whole bytes}}
    %x = schedule.nba.acc.load %r[value] {alignment = 1 : i64} : i7
    llvm.return %x : i7
  }
}

// -----

module {
  llvm.func @pending_not_valid(%r: !llvm.ptr) -> i64 {
    // expected-error @below {{tests a pending capture through a field other than valid}}
    %x = schedule.nba.acc.load %r[write_mask] {alignment = 8 : i64, pending_root = 1 : i32} : i64
    llvm.return %x : i64
  }
}

// -----

module {
  llvm.func @commit_not_mask(%r: !llvm.ptr) -> i32 {
    // expected-error @below {{reads a field other than write_mask at commit}}
    %x = schedule.nba.acc.load %r[valid] {alignment = 4 : i64, at_commit} : i32
    llvm.return %x : i32
  }
}

// -----

module {
  llvm.func @schedule_tag(%r: !llvm.ptr) -> i32 {
    // expected-error @below {{carries the schedule fact 'schedule.eval.pending_dirty_root' as a property, not an attribute}}
    %x = schedule.nba.acc.load %r[valid] {alignment = 4 : i64, schedule.eval.pending_dirty_root = 1 : i32} : i32
    llvm.return %x : i32
  }
}

// -----

module {
  llvm.func @no_record() -> !llvm.ptr {
    // expected-error @below {{must reference the llvm.mlir.global of its record}}
    %r = schedule.nba.acc.address @missing : !llvm.ptr
    llvm.return %r : !llvm.ptr
  }
}

// -----

module {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @table() : !llvm.ptr {
    // expected-error @below {{must be in a function}}
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    llvm.return %r : !llvm.ptr
  }
}

// -----

module {
  llvm.func @offset_past_field(%r: !llvm.ptr) -> i8 {
    // expected-error @below {{accesses bytes outside its valid field}}
    %x = schedule.nba.acc.load %r[valid + 8] {alignment = 1 : i64} : i8
    llvm.return %x : i8
  }
}

// -----

module {
  llvm.func @unknown_field(%r: !llvm.ptr) -> i64 {
    // expected-error @below {{unknown NBA accumulator field 'stage'}}
    %x = schedule.nba.acc.load %r[stage] {alignment = 8 : i64} : i64
    llvm.return %x : i64
  }
}
