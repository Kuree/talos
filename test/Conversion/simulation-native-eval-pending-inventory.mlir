// RUN: talos-opt %s --split-input-file --materialize-native-eval-transactions | FileCheck %s

// The eval transaction moves a certified root's NBA capture into a private
// frame only when it sees every access to it. Each NBA update keeps the
// values in effect when it was placed in the NBA region and is consumed once
// (IEEE 1800-2023 4.9.4, 10.4.2). The first two splits localize root 0; each
// later root changes one fact of it and stays canonical. The certificate's
// root array holds the root (1), its destination (2), width (4), write mask
// (5) and region (6); a capture mark holds the root, then destination, width,
// mask, region and site.

// A localized root's capture lives in the frame: the root's bit of the bitmap
// word at offset 0 and its masked value at offset 8. The commit reads the
// write mask only where the root is staged, so an at_commit read is the
// certified mask; any other read is that mask only while the bit is set.
// CHECK-LABEL: llvm.func internal @stage.__talos_pending(
// CHECK-SAME: %[[V:.*]]: i64, %[[FRAME:.*]]: !llvm.ptr {llvm.noalias, llvm.nocapture}) -> i64
// CHECK-NEXT: schedule.nba.acc.address @acc
// CHECK-NEXT: %[[LANE:.*]] = llvm.getelementptr %[[FRAME]][8]
// CHECK-NEXT: %[[MASK:.*]] = llvm.mlir.constant(65280 : i64) : i64
// CHECK-NEXT: %[[BITS:.*]] = llvm.and %[[V]], %[[MASK]] : i64
// CHECK-NEXT: llvm.store %[[BITS]], %[[LANE]]
// CHECK: llvm.zext %{{.*}} : i1 to i32
// CHECK-NEXT: %[[COMMITTED:.*]] = llvm.mlir.constant(65280 : i64) : i64
// CHECK-NEXT: %[[WORD_ADDRESS:.*]] = llvm.getelementptr %[[FRAME]][0]
// CHECK-NEXT: %[[WORD:.*]] = llvm.load %[[WORD_ADDRESS]]
// CHECK-NEXT: %[[BIT:.*]] = llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[OWN:.*]] = llvm.and %[[WORD]], %[[BIT]] : i64
// CHECK-NEXT: %[[NONE:.*]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[STAGED:.*]] = llvm.icmp "ne" %[[OWN]], %[[NONE]] : i64
// CHECK-NEXT: %[[CERTIFIED:.*]] = llvm.mlir.constant(65280 : i64) : i64
// CHECK-NEXT: %[[EMPTY:.*]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[PENDING:.*]] = llvm.select %[[STAGED]], %[[CERTIFIED]], %[[EMPTY]] : i1, i64
// CHECK-NEXT: %[[MASKS:.*]] = llvm.xor %[[COMMITTED]], %[[PENDING]] : i64
// CHECK-NEXT: llvm.return %[[MASKS]] : i64
// CHECK-LABEL: llvm.func @stage(
// CHECK: llvm.call @stage.__talos_pending(
module attributes {schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 65280, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr
  llvm.func @stage(%v: i64) -> i64 attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    schedule.nba.acc.store %v, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 65280, 2, 1>, root = 0 : i32}
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    %committed = schedule.nba.acc.load %acc[write_mask] {alignment = 8 : i64, at_commit} : i64
    %pending = schedule.nba.acc.load %acc[write_mask] {alignment = 8 : i64} : i64
    %masks = llvm.xor %committed, %pending : i64
    llvm.return %masks : i64
  }
}

// -----

// A runtime NBA call is an opaque cut around which the transaction exports
// and adopts its captures; by itself it keeps no root canonical.
// CHECK-LABEL: llvm.func internal @routed.__talos_pending(
// CHECK: llvm.call @talos_rt_v1_scheduler_nba(
// CHECK-LABEL: llvm.func @routed(
// CHECK: llvm.call @routed.__talos_pending(
module attributes {schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 65280, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @routed(%v: i64, %c: !llvm.ptr) attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    schedule.nba.acc.store %v, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 65280, 2, 1>, root = 0 : i32}
    %s = llvm.call @talos_rt_v1_scheduler_nba(%c, %c, %c, %v, %v, %v, %v, %c, %c) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    llvm.return
  }
}

// -----

// The certificate lists every NBA site of the root. Site 2 has no generated
// capture here: the runtime call above may be it. A root whose sites are not
// all captured stays canonical, so the runtime's NBA and the generated one
// stay in execution order (4.6(b)).
// CHECK-LABEL: llvm.func @site_count(
// CHECK-NOT: __talos_pending
// CHECK: llvm.return
module attributes {schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 65280, 2, 0>, accumulator = @acc, sites = array<i64: 1, 2>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @site_count(%v: i64, %c: !llvm.ptr) attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    schedule.nba.acc.store %v, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 65280, 2, 1>, root = 0 : i32}
    %s = llvm.call @talos_rt_v1_scheduler_nba(%c, %c, %c, %v, %v, %v, %v, %c, %c) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    llvm.return
  }
}

// -----

// Each root below changes one fact of root 0 of the first split, which a
// localized root needs: its capture's site, destination, width, mask and
// region are the certified ones, and its mask is not empty; its captures
// agree; the consumer that commits it is its accumulator's; the runtime holds
// no capture of it; and every access of its record is a typed access of the
// first word of a field, of 64 bits (32 for the flags).
// CHECK-LABEL: llvm.func @mismatches(
// CHECK-NOT: __talos_pending
// CHECK: llvm.return
module attributes {schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [
    {root = array<i64: 1, 0, 1, 0, 32, 65280, 2, 0>, accumulator = @site, sites = array<i64: 13>},
    {root = array<i64: 1, 1, 1, 0, 32, 65280, 2, 0>, accumulator = @destination, sites = array<i64: 2>},
    {root = array<i64: 1, 2, 1, 0, 32, 65280, 2, 0>, accumulator = @width, sites = array<i64: 3>},
    {root = array<i64: 1, 3, 1, 0, 32, 65280, 2, 0>, accumulator = @mask, sites = array<i64: 4>},
    {root = array<i64: 1, 4, 1, 0, 32, 0, 2, 0>, accumulator = @empty, sites = array<i64: 5>},
    {root = array<i64: 1, 5, 1, 0, 32, 65280, 2, 0>, accumulator = @region, sites = array<i64: 6>},
    {root = array<i64: 1, 6, 1, 0, 32, 65280, 2, 0>, accumulator = @twice, sites = array<i64: 7>},
    {root = array<i64: 1, 7, 1, 0, 32, 65280, 2, 0>, accumulator = @consumed, sites = array<i64: 8>},
    {root = array<i64: 1, 8, 1, 0, 32, 65280, 2, 0>, accumulator = @held, sites = array<i64: 9>},
    {root = array<i64: 1, 9, 1, 0, 32, 65280, 2, 0>, accumulator = @aliased, sites = array<i64: 10>},
    {root = array<i64: 1, 10, 1, 0, 32, 65280, 2, 0>, accumulator = @offset, sites = array<i64: 11>},
    {root = array<i64: 1, 11, 1, 0, 32, 65280, 2, 0>, accumulator = @narrow, sites = array<i64: 12>}]} {
  llvm.mlir.global internal @site(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @destination(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @width(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @mask(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @empty(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @region(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @twice(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @consumed(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @held(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @aliased(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @offset(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @narrow(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @other(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr
  llvm.func @mismatches(%v: i64, %w: i32, %c: i1) attributes {schedule.eval.call_closure_root} {
    %other = schedule.nba.acc.address @other : !llvm.ptr
    // Root 0: its capture is of site 1, not the certified site 13.
    %site = schedule.nba.acc.address @site : !llvm.ptr
    schedule.nba.acc.store %v, %site[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 65280, 2, 1>, root = 0 : i32}
    %site.present = schedule.nba.acc.load %site[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    // Root 1: its capture writes another destination.
    %destination = schedule.nba.acc.address @destination : !llvm.ptr
    schedule.nba.acc.store %v, %destination[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 1, 2, 32, 65280, 2, 2>, root = 1 : i32}
    %destination.present = schedule.nba.acc.load %destination[valid] {alignment = 4 : i64, pending_root = 1 : i32} : i32
    // Root 2: its capture is narrower.
    %width = schedule.nba.acc.address @width : !llvm.ptr
    schedule.nba.acc.store %v, %width[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 2, 1, 16, 65280, 2, 3>, root = 2 : i32}
    %width.present = schedule.nba.acc.load %width[valid] {alignment = 4 : i64, pending_root = 2 : i32} : i32
    // Root 3: its capture writes another mask.
    %mask = schedule.nba.acc.address @mask : !llvm.ptr
    schedule.nba.acc.store %v, %mask[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 3, 1, 32, 255, 2, 4>, root = 3 : i32}
    %mask.present = schedule.nba.acc.load %mask[valid] {alignment = 4 : i64, pending_root = 3 : i32} : i32
    // Root 4: its capture writes no bits.
    %empty = schedule.nba.acc.address @empty : !llvm.ptr
    schedule.nba.acc.store %v, %empty[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 4, 1, 32, 0, 2, 5>, root = 4 : i32}
    %empty.present = schedule.nba.acc.load %empty[valid] {alignment = 4 : i64, pending_root = 4 : i32} : i32
    // Root 5: its capture commits in another region.
    %region = schedule.nba.acc.address @region : !llvm.ptr
    schedule.nba.acc.store %v, %region[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 5, 1, 32, 65280, 1, 6>, root = 5 : i32}
    %region.present = schedule.nba.acc.load %region[valid] {alignment = 4 : i64, pending_root = 5 : i32} : i32
    // Root 6: two of its captures disagree on its width.
    %twice = schedule.nba.acc.address @twice : !llvm.ptr
    schedule.nba.acc.store %v, %twice[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 6, 1, 32, 65280, 2, 7>, root = 6 : i32}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 6, 1, 16, 65280, 2, 7>, root = 6 : i32}
    %twice.present = schedule.nba.acc.load %twice[valid] {alignment = 4 : i64, pending_root = 6 : i32} : i32
    // Root 7: the consumer that commits it is of another accumulator.
    %consumed = schedule.nba.acc.address @consumed : !llvm.ptr
    schedule.nba.acc.store %v, %consumed[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 7, 1, 32, 65280, 2, 8>, root = 7 : i32}
    %consumed.present = schedule.nba.acc.load %other[valid] {alignment = 4 : i64, pending_root = 7 : i32} : i32
    // Root 8: the runtime holds a capture of it.
    %held = schedule.nba.acc.address @held : !llvm.ptr
    schedule.nba.acc.store %v, %held[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 8, 1, 32, 65280, 2, 9>, root = 8 : i32}
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {canonical_capture, root = 8 : i32}
    %held.present = schedule.nba.acc.load %held[valid] {alignment = 4 : i64, pending_root = 8 : i32} : i32
    // Root 9: its record flows into a select, through which a store is not
    // one of the record's.
    %aliased = schedule.nba.acc.address @aliased : !llvm.ptr
    schedule.nba.acc.store %v, %aliased[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 9, 1, 32, 65280, 2, 10>, root = 9 : i32}
    %aliased.alias = llvm.select %c, %aliased, %aliased : i1, !llvm.ptr
    schedule.nba.acc.store %v, %aliased.alias[value] {alignment = 8 : i64} : i64
    %aliased.present = schedule.nba.acc.load %aliased[valid] {alignment = 4 : i64, pending_root = 9 : i32} : i32
    // Root 10: an access is into a field, past its first word.
    %offset = schedule.nba.acc.address @offset : !llvm.ptr
    schedule.nba.acc.store %v, %offset[value + 8] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 10, 1, 32, 65280, 2, 11>, root = 10 : i32}
    %offset.present = schedule.nba.acc.load %offset[valid] {alignment = 4 : i64, pending_root = 10 : i32} : i32
    // Root 11: an access is of 32 bits of a 64-bit field.
    %narrow = schedule.nba.acc.address @narrow : !llvm.ptr
    schedule.nba.acc.store %w, %narrow[value] {alignment = 4 : i64} : i32
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 11, 1, 32, 65280, 2, 12>, root = 11 : i32}
    %narrow.present = schedule.nba.acc.load %narrow[valid] {alignment = 4 : i64, pending_root = 11 : i32} : i32
    llvm.return
  }
}

// -----

// An LLVM address of the readiness index is an access the transaction cannot
// project onto the private index, so no root is localized.
// CHECK-LABEL: llvm.func @raw_summary(
// CHECK-NOT: __talos_pending
// CHECK: llvm.return
module attributes {schedule.eval.runtime_calendar, schedule.eval.transaction_roots = [{root = array<i64: 1, 0, 1, 0, 32, 65280, 2, 0>, accumulator = @acc, sites = array<i64: 1>}]} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr
  llvm.func @raw_summary(%v: i64) -> !llvm.ptr attributes {schedule.eval.call_closure_root} {
    %acc = schedule.nba.acc.address @acc : !llvm.ptr
    schedule.nba.acc.store %v, %acc[value] {alignment = 8 : i64} : i64
    schedule.nba.index.store %v, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 1, 32, 65280, 2, 1>, root = 0 : i32}
    %present = schedule.nba.acc.load %acc[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    %summary = llvm.mlir.addressof @__talos_aot_nba_dirty_summary_v1 : !llvm.ptr
    llvm.return %summary : !llvm.ptr
  }
}
