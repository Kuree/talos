// RUN: talos-opt %s --convert-native-schedule-actions-to-llvm=coalesce=false | FileCheck %s --implicit-check-not=schedule.ready.update --implicit-check-not=schedule.ready.commit --implicit-check-not=schedule.ready.read

// Each ready action becomes typed word accesses of its set in the
// DirtyReadySetLayout of its capacity: an add ORs its leaf, then the bit of
// that leaf into the word at offsets[level] + parent of every dirty level,
// selected by whether the add may be nonzero; a consume clears only its leaf.
// Capacity 4096 has 64 leaves and one dirty word, 64. Capacity 262144 has
// 4096 leaves, dirty words 4096-4159 and a top word 4160.
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<4161 x i64>
  // CHECK-LABEL: llvm.func @add(
  // CHECK-SAME: %[[BITS:.*]]: i64)
  // CHECK-NEXT: %[[LEAF:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[63]
  // CHECK-NEXT: %[[SET:.*]] = arith.ori %[[LEAF]], %[[BITS]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[SET]], @__talos_aot_model_ingress_v1[63]
  // CHECK-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[ANY:.*]] = arith.cmpi ne, %[[BITS]], %[[ZERO]] : i64
  // CHECK-NEXT: %[[BIT:.*]] = llvm.mlir.constant(-9223372036854775808 : i64) : i64
  // CHECK-NEXT: %[[NONE:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[MARK:.*]] = arith.select %[[ANY]], %[[BIT]], %[[NONE]] : i64
  // CHECK-NEXT: %[[DIRTY:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[64]
  // CHECK-NEXT: %[[MARKED:.*]] = arith.ori %[[DIRTY]], %[[MARK]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[MARKED]], @__talos_aot_model_ingress_v1[64]
  // CHECK-NEXT: llvm.return
  llvm.func @add(%bits: i64) {
    schedule.ready.update @__talos_aot_model_ingress_v1[63], %bits {capacity = 4096 : i64, consume = false}
    llvm.return
  }
  // CHECK-LABEL: llvm.func @consume(
  // CHECK-SAME: %[[BITS:.*]]: i64)
  // CHECK-NEXT: %[[LEAF:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[63]
  // CHECK-NEXT: %[[ONES:.*]] = llvm.mlir.constant(-1 : i64) : i64
  // CHECK-NEXT: %[[KEEP:.*]] = arith.xori %[[BITS]], %[[ONES]] : i64
  // CHECK-NEXT: %[[LEFT:.*]] = arith.andi %[[LEAF]], %[[KEEP]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[LEFT]], @__talos_aot_model_ingress_v1[63]
  // CHECK-NEXT: llvm.return
  llvm.func @consume(%bits: i64) {
    schedule.ready.update @__talos_aot_model_ingress_v1[63], %bits {capacity = 4096 : i64, consume = true}
    llvm.return
  }
  // A commit writes its leaf once, then marks bit 0 of dirty word 64 when its
  // add mask may be nonzero.
  // CHECK-LABEL: llvm.func @commit(
  // CHECK-SAME: %[[REMOVE:.*]]: i64, %[[ADD:.*]]: i64)
  // CHECK-NEXT: %[[LEAF:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: %[[ONES:.*]] = llvm.mlir.constant(-1 : i64) : i64
  // CHECK-NEXT: %[[KEEP:.*]] = arith.xori %[[REMOVE]], %[[ONES]] : i64
  // CHECK-NEXT: %[[LEFT:.*]] = arith.andi %[[LEAF]], %[[KEEP]] : i64
  // CHECK-NEXT: %[[NEXT:.*]] = arith.ori %[[LEFT]], %[[ADD]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[NEXT]], @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[ANY:.*]] = arith.cmpi ne, %[[ADD]], %[[ZERO]] : i64
  // CHECK-NEXT: %[[BIT:.*]] = llvm.mlir.constant(1 : i64) : i64
  // CHECK-NEXT: %[[NONE:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[MARK:.*]] = arith.select %[[ANY]], %[[BIT]], %[[NONE]] : i64
  // CHECK-NEXT: %[[DIRTY:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[64]
  // CHECK-NEXT: %[[MARKED:.*]] = arith.ori %[[DIRTY]], %[[MARK]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[MARKED]], @__talos_aot_model_ingress_v1[64]
  // CHECK-NEXT: llvm.return
  llvm.func @commit(%remove: i64, %add: i64) {
    schedule.ready.commit @__talos_aot_model_ingress_v1[0], %remove, %add {capacity = 4096 : i64}
    llvm.return
  }
  // Leaf 4095 marks bit 63 of dirty word 4096 + 4095 / 64 = 4159, and leaf
  // word 63 of that level marks bit 63 of the top word 4160.
  // CHECK-LABEL: llvm.func @two_levels(
  // CHECK-SAME: %[[BITS:.*]]: i64)
  // CHECK-NEXT: %[[LEAF:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[4095]
  // CHECK-NEXT: %[[SET:.*]] = arith.ori %[[LEAF]], %[[BITS]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[SET]], @__talos_aot_model_ingress_v1[4095]
  // CHECK-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[ANY:.*]] = arith.cmpi ne, %[[BITS]], %[[ZERO]] : i64
  // CHECK-NEXT: %[[BIT1:.*]] = llvm.mlir.constant(-9223372036854775808 : i64) : i64
  // CHECK-NEXT: %[[NONE1:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[MARK1:.*]] = arith.select %[[ANY]], %[[BIT1]], %[[NONE1]] : i64
  // CHECK-NEXT: %[[DIRTY1:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[4159]
  // CHECK-NEXT: %[[MARKED1:.*]] = arith.ori %[[DIRTY1]], %[[MARK1]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[MARKED1]], @__talos_aot_model_ingress_v1[4159]
  // CHECK-NEXT: %[[BIT2:.*]] = llvm.mlir.constant(-9223372036854775808 : i64) : i64
  // CHECK-NEXT: %[[NONE2:.*]] = llvm.mlir.constant(0 : i64) : i64
  // CHECK-NEXT: %[[MARK2:.*]] = arith.select %[[ANY]], %[[BIT2]], %[[NONE2]] : i64
  // CHECK-NEXT: %[[DIRTY2:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[4160]
  // CHECK-NEXT: %[[MARKED2:.*]] = arith.ori %[[DIRTY2]], %[[MARK2]] : i64
  // CHECK-NEXT: schedule.ready.word.store %[[MARKED2]], @__talos_aot_model_ingress_v1[4160]
  // CHECK-NEXT: llvm.return
  llvm.func @two_levels(%bits: i64) {
    schedule.ready.update @__talos_aot_model_ingress_v1[4095], %bits {capacity = 262144 : i64, consume = false}
    llvm.return
  }
  // A read is a load of its leaf, which keeps its activation entry.
  // CHECK-LABEL: llvm.func @read()
  // CHECK-NEXT: %[[LEAF:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[5] {activation_entry = 7 : i32}
  // CHECK-NEXT: llvm.return %[[LEAF]] : i64
  llvm.func @read() -> i64 {
    %pending = schedule.ready.read @__talos_aot_model_ingress_v1[5] {capacity = 4096 : i64, schedule.eval.activation_entry = 7 : i32}
    llvm.return %pending : i64
  }
}
