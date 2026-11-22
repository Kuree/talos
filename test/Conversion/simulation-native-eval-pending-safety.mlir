// RUN: talos-opt %s --split-input-file --finalize-native-llvm | FileCheck %s
// RUN: talos-opt %s --split-input-file --finalize-native-llvm --mlir-disable-threading | FileCheck %s
// RUN: talos-opt %s --split-input-file --finalize-native-llvm -o /dev/null 2>&1 | FileCheck %s --check-prefix=CUT --implicit-check-not='external cut: talos_rt_v1_scheduler_time'

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

// -----

// A runtime-routed static NBA stage, of this or another root, is no
// transaction-local call: the transaction exports its private captures
// before it and adopts them again after it, as around any opaque call. NBAs to one variable stay
// in execution order (IEEE 1800-2023 4.6(b), 10.4.2).
// CUT: talos eval pending external cut: talos_rt_v1_scheduler_static_nba sites=1
// CUT: talos eval pending external cut: talos_rt_v1_static_nba_claim sites=1
// CUT: talos eval pending external cut: talos_rt_v1_static_nba_stage_wide sites=1
// CHECK-LABEL: llvm.func internal @work.__talos_pending(
// CHECK-SAME: %{{.*}}: i64, %[[FRAME:[^:]*]]: !llvm.ptr
// CHECK: %[[RECORD:.*]] = llvm.mlir.addressof @acc
// CHECK-NEXT: %[[SLOT:.*]] = llvm.getelementptr %[[FRAME]][8]
// CHECK-NEXT: %[[PRIVATE:.*]] = llvm.load %[[SLOT]]
// CHECK-NEXT: %[[FIELD:.*]] = llvm.getelementptr %[[RECORD]][0]
// CHECK-NEXT: llvm.store %[[PRIVATE]], %[[FIELD]]
// CHECK: llvm.call @talos_rt_v1_static_nba_claim(
// CHECK: %[[ADOPTED:.*]] = llvm.mlir.addressof @acc
// CHECK: llvm.call @talos_rt_v1_static_nba_specialization_guard(
// CHECK: %[[STAGED:.*]] = llvm.getelementptr %[[ADOPTED]][0]
// CHECK-NEXT: %[[VALUE:.*]] = llvm.load %[[STAGED]]
// CHECK-NEXT: %[[BACK:.*]] = llvm.getelementptr %[[FRAME]][8]
// CHECK-NEXT: llvm.store %[[VALUE]], %[[BACK]]
// CHECK: llvm.mlir.addressof @acc
// CHECK-NEXT: llvm.getelementptr %[[FRAME]][8]
// CHECK: llvm.call @talos_rt_v1_static_nba_stage_wide(
// CHECK: llvm.call @talos_rt_v1_static_nba_specialization_guard(
// CHECK: llvm.mlir.addressof @acc
// CHECK-NEXT: llvm.getelementptr %[[FRAME]][8]
// CHECK: llvm.call @talos_rt_v1_scheduler_static_nba(
// CHECK: llvm.call @talos_rt_v1_static_nba_specialization_guard(
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.debug_timing, schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_static_nba_claim(!llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, i64) -> i32
  llvm.func @talos_rt_v1_static_nba_stage_wide(!llvm.ptr, i32, i64, i64, i64, i64, i32)
  llvm.func @talos_rt_v1_scheduler_static_nba(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
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
    %context = llvm.mlir.zero : !llvm.ptr
    %other = llvm.mlir.constant(7 : i32) : i32
    %claimed = llvm.call @talos_rt_v1_static_nba_claim(%context, %other, %context, %context, %arg, %arg, %arg, %arg, %arg) : (!llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, i64) -> i32
    llvm.call @talos_rt_v1_static_nba_stage_wide(%context, %other, %arg, %arg, %arg, %arg, %zero) : (!llvm.ptr, i32, i64, i64, i64, i64, i32) -> ()
    %staged = llvm.call @talos_rt_v1_scheduler_static_nba(%context, %arg, %context, %context, %arg, %arg, %arg, %context, %context) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return
  }
}

// -----

// A runtime entry the catalog marks PendingTransparent, such as the time
// query, cannot read, stage or consume a pending capture: the private capture
// stays in the frame across it. Reporting a status is not one: the
// transaction exports the capture before it and adopts it again after it,
// as around any opaque call (IEEE 1800-2023 4.6(b), 10.4.2).
// CUT: talos eval pending external cut: talos_rt_v1_scheduler_report_status sites=1
// CHECK-LABEL: llvm.func internal @work.__talos_pending(
// CHECK-NOT: llvm.mlir.addressof @acc
// CHECK: llvm.call @talos_rt_v1_scheduler_time(
// CHECK: llvm.mlir.addressof @acc
// CHECK: llvm.call @talos_rt_v1_scheduler_report_status(
// CHECK: llvm.call @talos_rt_v1_static_nba_specialization_guard(
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.debug_timing, schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_scheduler_time(!llvm.ptr) -> i64
  llvm.func @talos_rt_v1_scheduler_report_status(!llvm.ptr, i32)
  llvm.func @work(%arg: i64) -> i64 attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    %zero = llvm.mlir.constant(0 : i32) : i32
    schedule.nba.acc.store %arg, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %arg, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    %marked = llvm.mlir.constant(1 : i64) : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 4294967295, 2, 1>, root = 0 : i32}
    %context = llvm.mlir.zero : !llvm.ptr
    %now = llvm.call @talos_rt_v1_scheduler_time(%context) : (!llvm.ptr) -> i64
    llvm.call @talos_rt_v1_scheduler_report_status(%context, %zero) : (!llvm.ptr, i32) -> ()
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return %now : i64
  }
}
