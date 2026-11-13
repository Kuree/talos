// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(func.func(talos-native-cleanup-function))' | FileCheck %s

// Packed lowering materializes a constant at each use. In an optimized module
// the lowered function is canonicalized and CSE'd before LLVM conversion:
// one constant per value, folded identities gone, repeated address
// computations merged.

// CHECK-LABEL: func.func @lowered(
// CHECK-SAME: %[[X:.*]]: i64
// CHECK-DAG: %[[MASK:.*]] = arith.constant 255 : i64
// CHECK-DAG: %[[PLANE:.*]] = llvm.mlir.addressof @plane
// CHECK-NOT: arith.constant 255
// CHECK-NOT: llvm.mlir.addressof
// CHECK: %[[LOW:.*]] = arith.andi %[[X]], %[[MASK]]
// CHECK-NEXT: %[[ADDRESS:.*]] = llvm.getelementptr %[[PLANE]][8]
// CHECK-NEXT: llvm.store %[[LOW]], %[[ADDRESS]]
// CHECK-NEXT: %[[AGAIN:.*]] = llvm.load %[[ADDRESS]]
// CHECK-NEXT: %[[BOTH:.*]] = arith.andi %[[AGAIN]], %[[MASK]]
// CHECK-NEXT: return %[[BOTH]]
module attributes {native.optimization_level = 3 : i32} {
  llvm.mlir.global internal @plane() : !llvm.array<16 x i8>
  func.func @lowered(%x: i64) -> i64 {
    %zero = arith.constant 0 : i64
    %shifted = arith.shli %x, %zero : i64
    %mask = arith.constant 255 : i64
    %low = arith.andi %shifted, %mask : i64
    %plane = llvm.mlir.addressof @plane : !llvm.ptr
    %address = llvm.getelementptr %plane[8] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %low, %address : i64, !llvm.ptr
    %plane2 = llvm.mlir.addressof @plane : !llvm.ptr
    %address2 = llvm.getelementptr %plane2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %again = llvm.load %address2 : !llvm.ptr -> i64
    %mask2 = arith.constant 255 : i64
    %both = arith.andi %again, %mask2 : i64
    return %both : i64
  }
}

// -----

// Without optimization the lowered IR is left for the final LLVM cleanup.

// CHECK-LABEL: func.func @unoptimized(
// CHECK: arith.constant 0 : i64
// CHECK-NEXT: arith.shli
// CHECK-NEXT: return
module attributes {native.optimization_level = 0 : i32} {
  func.func @unoptimized(%x: i64) -> i64 {
    %zero = arith.constant 0 : i64
    %shifted = arith.shli %x, %zero : i64
    return %shifted : i64
  }
}

// -----

// No block merging: two blocks that differ only in the scratch allocation
// they mark stay apart, so each lifetime marker still names its allocation
// (LLVM rejects one on a block argument).

// CHECK-LABEL: func.func @scratch(
// CHECK: %[[A:.*]] = llvm.alloca
// CHECK: %[[B:.*]] = llvm.alloca
// CHECK: llvm.intr.lifetime.start %[[A]]
// CHECK: llvm.intr.lifetime.end %[[A]]
// CHECK: llvm.intr.lifetime.start %[[B]]
// CHECK: llvm.intr.lifetime.end %[[B]]
module attributes {native.optimization_level = 3 : i32} {
  func.func @scratch(%c: i1) {
    %one = arith.constant 1 : i64
    %a = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    %b = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    cf.cond_br %c, ^left, ^right
  ^left:
    llvm.intr.lifetime.start %a : !llvm.ptr
    llvm.intr.lifetime.end %a : !llvm.ptr
    cf.br ^done
  ^right:
    llvm.intr.lifetime.start %b : !llvm.ptr
    llvm.intr.lifetime.end %b : !llvm.ptr
    cf.br ^done
  ^done:
    return
  }
}

// -----

// The tags later native steps read stay on their operations: an NBA field
// GEP whose constant index folds into it keeps its field, and a store keeps
// its unknown write range. Equal tagged addresses merge.

// CHECK-LABEL: func.func @tagged(
// CHECK: %[[BASE:.*]] = llvm.mlir.addressof @accumulator
// CHECK-NEXT: %[[FIELD:.*]] = llvm.getelementptr %[[BASE]][72] {native.nba_field = 72 : i64}
// CHECK-NEXT: llvm.store %{{.*}}, %[[FIELD]] {schedule.eval.unknown_write_range = array<i64: 0, 8>}
// CHECK-NEXT: llvm.load %[[FIELD]]
module attributes {native.optimization_level = 3 : i32} {
  llvm.mlir.global internal @accumulator() : !llvm.array<128 x i8>
  func.func @tagged(%v: i64) -> i64 {
    %k = llvm.mlir.constant(72 : i64) : i64
    %base = llvm.mlir.addressof @accumulator : !llvm.ptr
    %field = llvm.getelementptr %base[%k] {native.nba_field = 72 : i64} : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %v, %field {schedule.eval.unknown_write_range = array<i64: 0, 8>} : i64, !llvm.ptr
    %k2 = llvm.mlir.constant(72 : i64) : i64
    %base2 = llvm.mlir.addressof @accumulator : !llvm.ptr
    %field2 = llvm.getelementptr %base2[%k2] {native.nba_field = 72 : i64} : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %r = llvm.load %field2 : !llvm.ptr -> i64
    return %r : i64
  }
}
