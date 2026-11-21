// RUN: talos-opt %s --finalize-native-llvm | FileCheck %s

// LRM 20.2, 4.9.4: a finishing NBA preparation in the eval closure goes
// through the private-index wrapper, which cancels every sparse bitmap word
// before the next private consumer or wrapper export.
// ../Runtime/simulation-native-eval-pending-finish.test executes this
// self-checking program.
// CHECK-LABEL: llvm.func internal @__talos_eval_dispatch_v1.__talos_pending(
// CHECK: llvm.call @talos_rt_v1_scheduler_prepare_eval_nba_local_write(
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1()
// CHECK: llvm.call @__talos_eval_dispatch_v1.__talos_pending(

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.eval.runtime_calendar, schedule.eval.writable_vpi, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 4294967295, 2, 1>, accumulator = @acc0, sites = array<i64: 1>}, {root = array<i64: 65, 64, 65, 0, 32, 4294967295, 2, 0>, accumulator = @acc64, sites = array<i64: 2>}, {root = array<i64: 4097, 4096, 4097, 0, 32, 4294967295, 2, 0>, accumulator = @acc4096, sites = array<i64: 3>}]} {
  llvm.mlir.global @acc0(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global @acc64(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global @acc4096(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<520xi8>) : !llvm.array<520 x i8>
  llvm.mlir.global @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_scheduler_execute_aot_actor(!llvm.ptr, i32) -> i32
  llvm.func @talos_rt_v1_scheduler_prepare_eval_nba(!llvm.ptr, !llvm.ptr) -> i32

  llvm.func @capture0() {
    %acc = schedule.nba.acc.address @acc0 : !llvm.ptr
    %value = llvm.mlir.constant(1 : i64) : i64
    %unknown = llvm.mlir.constant(1 : i64) : i64
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    %one = llvm.mlir.constant(1 : i32) : i32
    %nba = llvm.mlir.constant(2 : i32) : i32
    %zero = llvm.mlir.constant(0 : i64) : i64
    schedule.nba.acc.store %value, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %unknown, %acc[unknown] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %nba, %acc[exec_region] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %zero, %acc[transient] {alignment = 8 : i64} : i64
    %old = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0] {root = 0 : i32}
    %bit = llvm.mlir.constant(1 : i64) : i64
    %marked = llvm.or %old, %bit : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 4294967295, 2, 1>, root = 0 : i32}
    %prior = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0] {root = 0 : i32}
    %pagebit = llvm.mlir.constant(1 : i64) : i64
    %markedpage = llvm.or %prior, %pagebit : i64
    schedule.nba.index.store %markedpage, @__talos_aot_nba_dirty_summary_v1[0] {root = 0 : i32}
    llvm.return
  }
  llvm.func @consume0() -> i64 {
    %acc = schedule.nba.acc.address @acc0 : !llvm.ptr
    %ready = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    %value = schedule.nba.acc.load %acc[value] {alignment = 8 : i64} : i64
    %unknown = schedule.nba.acc.load %acc[unknown] {alignment = 8 : i64} : i64
    %scale = llvm.mlir.constant(128 : i64) : i64
    %zero = llvm.mlir.constant(0 : i32) : i32
    %zero64 = llvm.mlir.constant(0 : i64) : i64
    %weighted = llvm.mul %unknown, %scale : i64
    %sum = llvm.add %value, %weighted : i64
    %present = llvm.icmp "ne" %ready, %zero : i32
    %result = llvm.select %present, %sum, %zero64 : i1, i64
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return %result : i64
  }
  llvm.func @capture64() {
    %acc = schedule.nba.acc.address @acc64 : !llvm.ptr
    %value = llvm.mlir.constant(2 : i64) : i64
    %unknown = llvm.mlir.constant(0 : i64) : i64
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    %one = llvm.mlir.constant(1 : i32) : i32
    %nba = llvm.mlir.constant(2 : i32) : i32
    %zero = llvm.mlir.constant(0 : i64) : i64
    schedule.nba.acc.store %value, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %unknown, %acc[unknown] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %nba, %acc[exec_region] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %zero, %acc[transient] {alignment = 8 : i64} : i64
    %old = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[1] {root = 64 : i32}
    %bit = llvm.mlir.constant(1 : i64) : i64
    %marked = llvm.or %old, %bit : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[1] {capture = array<i64: 64, 65, 32, 4294967295, 2, 2>, root = 64 : i32}
    %prior = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0] {root = 64 : i32}
    %pagebit = llvm.mlir.constant(2 : i64) : i64
    %markedpage = llvm.or %prior, %pagebit : i64
    schedule.nba.index.store %markedpage, @__talos_aot_nba_dirty_summary_v1[0] {root = 64 : i32}
    llvm.return
  }
  llvm.func @consume64() -> i64 {
    %acc = schedule.nba.acc.address @acc64 : !llvm.ptr
    %ready = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 64 : i32} : i32
    %value = schedule.nba.acc.load %acc[value] {alignment = 8 : i64} : i64
    %unknown = schedule.nba.acc.load %acc[unknown] {alignment = 8 : i64} : i64
    %scale = llvm.mlir.constant(128 : i64) : i64
    %zero = llvm.mlir.constant(0 : i32) : i32
    %zero64 = llvm.mlir.constant(0 : i64) : i64
    %weighted = llvm.mul %unknown, %scale : i64
    %sum = llvm.add %value, %weighted : i64
    %present = llvm.icmp "ne" %ready, %zero : i32
    %result = llvm.select %present, %sum, %zero64 : i1, i64
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return %result : i64
  }
  llvm.func @capture4096() {
    %acc = schedule.nba.acc.address @acc4096 : !llvm.ptr
    %value = llvm.mlir.constant(3 : i64) : i64
    %unknown = llvm.mlir.constant(0 : i64) : i64
    %bits = llvm.mlir.constant(4294967295 : i64) : i64
    %one = llvm.mlir.constant(1 : i32) : i32
    %nba = llvm.mlir.constant(2 : i32) : i32
    %zero = llvm.mlir.constant(0 : i64) : i64
    schedule.nba.acc.store %value, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %unknown, %acc[unknown] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %bits, %acc[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %one, %acc[valid] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %nba, %acc[exec_region] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %zero, %acc[transient] {alignment = 8 : i64} : i64
    %old = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[64] {root = 4096 : i32}
    %bit = llvm.mlir.constant(1 : i64) : i64
    %marked = llvm.or %old, %bit : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[64] {capture = array<i64: 4096, 4097, 32, 4294967295, 2, 3>, root = 4096 : i32}
    %prior = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[1] {root = 4096 : i32}
    %pagebit = llvm.mlir.constant(1 : i64) : i64
    %markedpage = llvm.or %prior, %pagebit : i64
    schedule.nba.index.store %markedpage, @__talos_aot_nba_dirty_summary_v1[1] {root = 4096 : i32}
    llvm.return
  }
  llvm.func @consume4096() -> i64 {
    %acc = schedule.nba.acc.address @acc4096 : !llvm.ptr
    %ready = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 4096 : i32} : i32
    %value = schedule.nba.acc.load %acc[value] {alignment = 8 : i64} : i64
    %unknown = schedule.nba.acc.load %acc[unknown] {alignment = 8 : i64} : i64
    %scale = llvm.mlir.constant(128 : i64) : i64
    %zero = llvm.mlir.constant(0 : i32) : i32
    %zero64 = llvm.mlir.constant(0 : i64) : i64
    %weighted = llvm.mul %unknown, %scale : i64
    %sum = llvm.add %value, %weighted : i64
    %present = llvm.icmp "ne" %ready, %zero : i32
    %result = llvm.select %present, %sum, %zero64 : i1, i64
    schedule.nba.acc.store %zero, %acc[valid] {alignment = 4 : i64} : i32
    llvm.return %result : i64
  }
  llvm.func @canonical_only() -> i64 {
    %bits = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[1] {canonical_capture, root = 5000 : i32}
    llvm.return %bits : i64
  }
  llvm.func @query() -> i64 {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %bits0 = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0]
    %sum0 = llvm.xor %zero, %bits0 : i64
    %bits1 = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[1]
    %sum1 = llvm.xor %sum0, %bits1 : i64
    %bits2 = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[64]
    %sum2 = llvm.xor %sum1, %bits2 : i64
    %bits3 = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0]
    %sum3 = llvm.xor %sum2, %bits3 : i64
    %bits4 = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[1]
    %sum4 = llvm.xor %sum3, %bits4 : i64
    llvm.return %sum4 : i64
  }
  llvm.func @pending4096() -> i64 {
    %bits = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[64] {root = 4096 : i32}
    %one = llvm.mlir.constant(1 : i64) : i64
    %result = llvm.and %bits, %one : i64
    llvm.return %result : i64
  }
  llvm.func @__talos_eval_dispatch_v1() -> i64 attributes {schedule.eval.call_closure_root} {
    %null = llvm.mlir.zero : !llvm.ptr
    %slot = llvm.mlir.constant(0 : i32) : i32
    %zero = llvm.mlir.constant(0 : i64) : i64
    llvm.call @capture0() : () -> ()
    llvm.call @capture64() : () -> ()
    llvm.call @capture4096() : () -> ()
    %canonical = llvm.call @canonical_only() : () -> i64
    %before = llvm.call @query() : () -> i64
    %expectedQuery = llvm.mlir.constant(3 : i64) : i64
    %queryOK = llvm.icmp "eq" %before, %expectedQuery : i64
    %last = llvm.call @pending4096() : () -> i64
    %one64 = llvm.mlir.constant(1 : i64) : i64
    %lastOK = llvm.icmp "eq" %last, %one64 : i64
    %one32 = llvm.mlir.constant(1 : i64) : i64
    %out = llvm.alloca %one32 x i32 : (i64) -> !llvm.ptr
    %status = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%null, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    %zero32 = llvm.mlir.constant(0 : i32) : i32
    %cutOK = llvm.icmp "eq" %status, %zero32 : i32
    %value0 = llvm.call @consume0() : () -> i64
    %sum0 = llvm.add %zero, %value0 : i64
    %value1 = llvm.call @consume64() : () -> i64
    %sum1 = llvm.add %sum0, %value1 : i64
    %value2 = llvm.call @consume4096() : () -> i64
    %sum2 = llvm.add %sum1, %value2 : i64
    schedule.nba.index.store %zero, @__talos_aot_nba_dirty_roots_v1[0]
    schedule.nba.index.store %zero, @__talos_aot_nba_dirty_roots_v1[1]
    schedule.nba.index.store %zero, @__talos_aot_nba_dirty_roots_v1[64]
    schedule.nba.index.store %zero, @__talos_aot_nba_dirty_summary_v1[0]
    schedule.nba.index.store %zero, @__talos_aot_nba_dirty_summary_v1[1]
    %after = llvm.call @query() : () -> i64
    %empty = llvm.icmp "eq" %after, %zero : i64
    %validCut = llvm.and %queryOK, %cutOK : i1
    %validLast = llvm.and %validCut, %lastOK : i1
    %valid = llvm.and %validLast, %empty : i1
    %failure = llvm.mlir.constant(-1 : i64) : i64
    %result = llvm.select %valid, %sum2, %failure : i1, i64
    llvm.return %result : i64
  }
  llvm.func @main() -> i32 {
    %first = llvm.call @__talos_eval_dispatch_v1() : () -> i64
    %second = llvm.call @__talos_eval_dispatch_v1() : () -> i64
    %expected = llvm.mlir.constant(0 : i64) : i64
    %one = llvm.mlir.constant(1 : i32) : i32
    %zero = llvm.mlir.constant(0 : i32) : i32
    %firstOK = llvm.icmp "eq" %first, %expected : i64
    %secondOK = llvm.icmp "eq" %second, %expected : i64
    %reentryOK = llvm.and %firstOK, %secondOK : i1
    %ok = llvm.and %firstOK, %secondOK : i1
    %status = llvm.select %ok, %zero, %one : i1, i32
    llvm.return %status : i32
  }
}
