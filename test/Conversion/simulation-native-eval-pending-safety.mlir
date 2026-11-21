// RUN: talos-opt %s --split-input-file --finalize-native-llvm | FileCheck %s
// RUN: talos-opt %s --split-input-file --finalize-native-llvm --mlir-disable-threading | FileCheck %s

// A generated private symbol must not collide with an existing LLVM symbol.
// CHECK-LABEL: llvm.func @work.__talos_pending()
// CHECK: llvm.func internal @[[CORE:work.__talos_pending_[0-9]+]](
// CHECK-LABEL: llvm.func @work(%{{.*}}: i64)
// CHECK: llvm.call @[[CORE]]
// CHECK: llvm.func internal @caller.__talos_pending(%{{.*}}: i64, %{{.*}}: !llvm.ptr {llvm.noalias, llvm.nocapture})
// CHECK: llvm.call @[[CORE]](%{{.*}}, %{{.*}}) {schedule.eval.direct_call} : (i64, !llvm.ptr) -> ()
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @work.__talos_pending()
  llvm.func @work(%arg: i64) attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    %zero = llvm.mlir.constant(0 : i32) : i32
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    schedule.nba.acc.store %bits, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    %marked = llvm.mlir.constant(1 : i64) : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 4294967295, 2, 1>, root = 0 : i32}
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return
  }
  llvm.func @caller(%arg: i64) attributes {schedule.eval.call_closure_root} {
    llvm.call @work(%arg) {schedule.eval.direct_call} : (i64) -> ()
    llvm.return
  }
}

// -----

// An LLVM address of the accumulator record can alias the capture through
// inttoptr; only typed accumulator accesses are visible to the transaction.
// LRM 4.9.4/10.4.2 requires one coherent captured payload. Keep it canonical.
// CHECK-LABEL: module attributes
// CHECK-NOT: .__talos_pending
// CHECK: llvm.func @work()
// CHECK-NOT: .__talos_pending
// CHECK: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @work() attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    %zero = llvm.mlir.constant(0 : i32) : i32
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    schedule.nba.acc.store %bits, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    %marked = llvm.mlir.constant(1 : i64) : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 4294967295, 2, 1>, root = 0 : i32}
    %raw = llvm.mlir.addressof @acc : !llvm.ptr
    %escaped = llvm.ptrtoint %raw : !llvm.ptr to i64
    %alias = llvm.inttoptr %escaped : i64 to !llvm.ptr
    llvm.store %bits, %alias : i64, !llvm.ptr
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return
  }
}

// -----

// A tail-call contract cannot carry an appended caller-owned frame. The ABI
// preflight must keep the whole transaction canonical before moving any body.
// CHECK-LABEL: module attributes
// CHECK-NOT: .__talos_pending
// CHECK: llvm.func @work(
// CHECK-NOT: .__talos_pending
// CHECK: llvm.call tail @work(
// CHECK-NOT: .__talos_pending
// CHECK: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @work(%arg: i64) attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    %zero = llvm.mlir.constant(0 : i32) : i32
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    schedule.nba.acc.store %bits, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    %marked = llvm.mlir.constant(1 : i64) : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 4294967295, 2, 1>, root = 0 : i32}
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return
  }
  llvm.func @caller(%arg: i64) attributes {schedule.eval.call_closure_root} {
    llvm.call tail @work(%arg) {schedule.eval.direct_call} : (i64) -> ()
    llvm.return
  }
}

// -----

// A dynamically addressed index can observe any canonical leaf. Retain the
// canonical ownership interface when the sparse projection is not exact.
// CHECK-LABEL: module attributes
// CHECK-NOT: .__talos_pending
// CHECK: llvm.func @work(
// CHECK-NOT: .__talos_pending
// CHECK: llvm.getelementptr %{{.*}}[%{{.*}}]
// CHECK-NOT: .__talos_pending
// CHECK: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @work(%word: i64) attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    %zero = llvm.mlir.constant(0 : i32) : i32
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    schedule.nba.acc.store %bits, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    %marked = llvm.mlir.constant(1 : i64) : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 4294967295, 2, 1>, root = 0 : i32}
    %opaqueIndex = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%word]
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return
  }
}
