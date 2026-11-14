// RUN: talos-opt %s | talos-opt | FileCheck %s --check-prefix=ROUND
// RUN: talos-opt %s --mlir-print-op-generic | talos-opt | FileCheck %s --check-prefix=ROUND
// RUN: talos-opt %s --emit-bytecode | talos-opt | FileCheck %s --check-prefix=ROUND
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(cse))' | FileCheck %s --check-prefix=CSE
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(canonicalize))' | FileCheck %s --check-prefix=CANON
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(sccp))' | FileCheck %s --check-prefix=SCCP

module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @use(!llvm.ptr)

  // Accesses round-trip with a static offset, a dynamic one, or both, and
  // with their properties, through custom and generic syntax and bytecode.
  // ROUND-LABEL: llvm.func @round(
  // ROUND: schedule.state.address @__talos_state_value : !llvm.ptr
  // ROUND: schedule.state.load @__talos_state_unknown[4] {alignment = 1 : i64, latch_destination, owner = 3 : i32, window = array<i64: 4, 5>} : i8
  // ROUND: schedule.state.load @__talos_state_value[%{{.*}}] {alignment = 1 : i64} : i8
  // ROUND: schedule.state.store %{{.*}}, @__talos_state_value[%{{.*}} + 8] {alignment = 8 : i64, latch_destination, owner = 1 : i32, summary_reported, window = array<i64: 0, 16>, written_bits = array<i64: 64, 64>} : i64
  // ROUND: schedule.state.window_address @__talos_state_unknown[%{{.*}} + 2] : !llvm.ptr
  // ROUND: schedule.state.window_address @__talos_state_value[6] : !llvm.ptr
  llvm.func @round(%v: i64, %d: i64) -> i8 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    %x = schedule.state.load @__talos_state_unknown[4] {alignment = 1 : i64, owner = 3 : i32, window = array<i64: 4, 5>, latch_destination} : i8
    %y = schedule.state.load @__talos_state_value[%d] {alignment = 1 : i64} : i8
    schedule.state.store %v, @__talos_state_value[%d + 8] {alignment = 8 : i64, window = array<i64: 0, 16>, written_bits = array<i64: 64, 64>, summary_reported, latch_destination, owner = 1 : i32} : i64
    %u = schedule.state.window_address @__talos_state_unknown[%d + 2] : !llvm.ptr
    %w = schedule.state.window_address @__talos_state_value[6] : !llvm.ptr
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    llvm.call @use(%u) : (!llvm.ptr) -> ()
    llvm.call @use(%w) : (!llvm.ptr) -> ()
    %s = llvm.add %x, %y : i8
    llvm.return %s : i8
  }

  // Plane addresses are constants: CSE keeps one per plane. Window addresses
  // are pure: CSE keeps one per window. Loads read and stores write memory:
  // CSE merges two loads of a window, not across a store.
  // CSE-LABEL: llvm.func @cse(
  // CSE: schedule.state.address @__talos_state_value
  // CSE-NOT: schedule.state.address
  // CSE: schedule.state.window_address @__talos_state_value[%{{.*}} + 4]
  // CSE-NOT: schedule.state.window_address
  // CSE: schedule.state.load @__talos_state_unknown[4]
  // CSE-NOT: schedule.state.load @__talos_state_unknown[4]
  // CSE: schedule.state.load @__talos_state_value[8]
  // CSE: schedule.state.store
  // CSE: schedule.state.load @__talos_state_value[8]
  // CSE: llvm.return
  llvm.func @cse(%v: i64, %d: i64) -> i64 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    %b = schedule.state.address @__talos_state_value : !llvm.ptr
    %wa = schedule.state.window_address @__talos_state_value[%d + 4] : !llvm.ptr
    %wb = schedule.state.window_address @__talos_state_value[%d + 4] : !llvm.ptr
    llvm.call @use(%wa) : (!llvm.ptr) -> ()
    llvm.call @use(%wb) : (!llvm.ptr) -> ()
    %x = schedule.state.load @__talos_state_unknown[4] {alignment = 1 : i64} : i8
    %y = schedule.state.load @__talos_state_unknown[4] {alignment = 1 : i64} : i8
    %z = schedule.state.load @__talos_state_value[8] {alignment = 8 : i64} : i64
    schedule.state.store %v, @__talos_state_value[8] {alignment = 8 : i64} : i64
    %w = schedule.state.load @__talos_state_value[8] {alignment = 8 : i64} : i64
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    llvm.call @use(%b) : (!llvm.ptr) -> ()
    %xy = llvm.add %x, %y : i8
    %e = llvm.zext %xy : i8 to i64
    %s = llvm.add %z, %w : i64
    %t = llvm.add %s, %e : i64
    llvm.return %t : i64
  }

  // Canonicalization hoists plane addresses like llvm.mlir.addressof and
  // folds a constant dynamic offset into the static one, of an access and
  // of a window address.
  // CANON-LABEL: llvm.func @canon(
  // CANON-NEXT: schedule.state.address @__talos_state_unknown
  // CANON-NOT: schedule.state.address
  // CANON: schedule.state.window_address @__talos_state_value[5] : !llvm.ptr
  // CANON: schedule.state.load @__talos_state_value[12] {alignment = 4 : i64} : i32
  // CANON: schedule.state.store %{{.*}}, @__talos_state_value[%{{.*}} + 6] {alignment = 2 : i64} : i16
  llvm.func @canon(%v: i16, %d: i64, %c: i1) -> i32 {
    %four = llvm.mlir.constant(4 : i64) : i64
    llvm.cond_br %c, ^left, ^right
  ^left:
    %a = schedule.state.address @__talos_state_unknown : !llvm.ptr
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    llvm.br ^right
  ^right:
    %b = schedule.state.address @__talos_state_unknown : !llvm.ptr
    llvm.call @use(%b) : (!llvm.ptr) -> ()
    %w = schedule.state.window_address @__talos_state_value[%four + 1] : !llvm.ptr
    llvm.call @use(%w) : (!llvm.ptr) -> ()
    %x = schedule.state.load @__talos_state_value[%four + 8] {alignment = 4 : i64} : i32
    schedule.state.store %v, @__talos_state_value[%d + 6] {alignment = 2 : i64} : i16
    llvm.return %x : i32
  }

  // SCCP propagates a plane address through a block argument only when every
  // edge passes the same plane; the value and unknown planes stay distinct.
  // SCCP-LABEL: llvm.func @sccp(
  // SCCP-DAG: %[[VALUE:.*]] = schedule.state.address @__talos_state_value
  // SCCP-DAG: %[[UNKNOWN:.*]] = schedule.state.address @__talos_state_unknown
  // SCCP: ^{{.*}}(%{{.*}}: !llvm.ptr):
  // SCCP-NEXT: llvm.call @use(%[[VALUE]])
  // SCCP: ^{{.*}}(%[[ARG:.*]]: !llvm.ptr):
  // SCCP-NEXT: llvm.call @use(%[[ARG]])
  llvm.func @sccp(%c: i1) {
    %value = schedule.state.address @__talos_state_value : !llvm.ptr
    %unknown = schedule.state.address @__talos_state_unknown : !llvm.ptr
    llvm.cond_br %c, ^same(%value : !llvm.ptr), ^same(%value : !llvm.ptr)
  ^same(%p: !llvm.ptr):
    llvm.call @use(%p) : (!llvm.ptr) -> ()
    llvm.cond_br %c, ^mixed(%value : !llvm.ptr), ^mixed(%unknown : !llvm.ptr)
  ^mixed(%q: !llvm.ptr):
    llvm.call @use(%q) : (!llvm.ptr) -> ()
    llvm.return
  }
}
