// RUN: talos-opt %s --convert-native-schedule-actions-to-llvm -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --mlir-disable-threading --convert-native-schedule-actions-to-llvm | diff %t -
// RUN: talos-opt %t --convert-native-schedule-actions-to-llvm | diff %t -
// RUN: talos-opt %s --schedule-coalesce-native-ready --convert-native-schedule-actions-to-llvm | FileCheck %s --check-prefix=OBS

// Bulk publication has a bounded CFG, no callback/runtime helper, and no
// per-leaf SSA expansion. Empty eight-word groups of a large source are
// skipped with one test. The runtime companion compares ascending merges
// against DirtyReadySetView for empty, sparse, dense, partial and aliased
// sources. Every merge names the model ingress, which the companion defines
// large enough for the largest layout and its sources.
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<8400 x i64>
  llvm.func @merge_1(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 1 : i64}
    llvm.return
  }
  llvm.func @merge_63(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 63 : i64}
    llvm.return
  }
  llvm.func @merge_64(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 64 : i64}
    llvm.return
  }
  llvm.func @merge_65(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 65 : i64}
    llvm.return
  }
  llvm.func @merge_128(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 128 : i64}
    llvm.return
  }
  // Fewer than two eight-word groups of unmasked words are merged word by
  // word; two or more are grouped.
  // CHECK-LABEL: llvm.func @merge_1023(
  // CHECK-NOT: vector
  // CHECK: llvm.return
  llvm.func @merge_1023(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 1023 : i64}
    llvm.return
  }
  // CHECK-LABEL: llvm.func @merge_1024(
  // CHECK: llvm.load {{.*}} -> vector<8xi64>
  // CHECK-NOT: -> vector<
  // CHECK: llvm.return
  llvm.func @merge_1024(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 1024 : i64}
    llvm.return
  }
  // CHECK-LABEL: llvm.func @merge_1216(
  // CHECK: llvm.load {{.*}} -> vector<8xi64>
  // CHECK-NOT: -> vector<
  // CHECK: llvm.load {{.*}} -> vector<3xi64>
  // CHECK-NOT: -> vector<
  // CHECK: llvm.return
  llvm.func @merge_1216(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 1216 : i64}
    llvm.return
  }
  llvm.func @merge_2048(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 2048 : i64}
    llvm.return
  }
  llvm.func @merge_2049(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 2049 : i64}
    llvm.return
  }
  llvm.func @merge_4096(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 4096 : i64}
    llvm.return
  }
  // Groups of eight words are tested at once, then the words after the last
  // whole group together. Only a nonempty group is merged word by word,
  // rereading each word just before its add, so the ascending read/add order
  // holds for an aliased source too. The last word, whose bits above capacity
  // are ignored, is masked once and added after every lower word.
  // CHECK-LABEL: llvm.func @merge_7553(
  // CHECK: %[[SET:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
  // CHECK-NOT: llvm.call
  // CHECK: cf.br ^[[GROUP:bb[0-9]+]]({{.*}} : i64)
  // CHECK: ^[[LAST:bb[0-9]+]]:
  // CHECK: %[[LASTINDEX:.*]] = llvm.mlir.constant(118 : i64)
  // CHECK: llvm.getelementptr %arg0[%[[LASTINDEX]]]
  // CHECK: %[[LASTWORD:.*]] = llvm.load
  // CHECK: %[[LASTBITS:.*]] = arith.andi %[[LASTWORD]],
  // CHECK: %[[LASTEMPTY:.*]] = arith.cmpi eq, %[[LASTBITS]],
  // CHECK: cf.cond_br %[[LASTEMPTY]], ^[[DONE:bb[0-9]+]], ^[[ADDLAST:bb[0-9]+]]
  // CHECK: ^[[ADDLAST]]:
  // CHECK: llvm.getelementptr %[[SET]][%[[LASTINDEX]]]
  // CHECK: arith.ori {{.*}}, %[[LASTBITS]]
  // CHECK: llvm.store
  // CHECK: arith.shrui %[[LASTINDEX]],
  // CHECK: llvm.store
  // CHECK-NEXT: cf.br ^[[DONE]]
  // CHECK: ^[[GROUP]](%[[START:.*]]: i64):
  // CHECK: %[[WHOLEEND:.*]] = llvm.mlir.constant(112 : i64)
  // CHECK: %[[GROUPSDONE:.*]] = arith.cmpi uge, %[[START]], %[[WHOLEEND]]
  // CHECK: cf.cond_br %[[GROUPSDONE]], ^[[REST:bb[0-9]+]], ^[[SCAN:bb[0-9]+]]
  // CHECK: ^[[HEAD:bb[0-9]+]](%[[WORD:.*]]: i64, %[[END:.*]]: i64):
  // CHECK: llvm.getelementptr %arg0[%[[WORD]]]
  // CHECK: %[[SOURCE:.*]] = llvm.load {{.*}} -> i64
  // CHECK-NOT: arith.select
  // CHECK: %[[EMPTY:.*]] = arith.cmpi eq, %[[SOURCE]],
  // CHECK: cf.cond_br %[[EMPTY]], ^[[ADVANCE:bb[0-9]+]], ^[[UPDATE:bb[0-9]+]]
  // Every add sets its dirty bit, without testing the leaf.
  // CHECK: ^[[UPDATE]]:
  // CHECK: llvm.getelementptr %[[SET]][%[[WORD]]]
  // CHECK: llvm.load
  // CHECK: llvm.store
  // CHECK-NOT: cf.cond_br
  // CHECK: arith.shrui %[[WORD]],
  // CHECK: llvm.store
  // CHECK-NEXT: cf.br ^[[ADVANCE]]
  // CHECK: ^[[ADVANCE]]:
  // CHECK: %[[FOLLOWING:.*]] = arith.addi %[[WORD]],
  // CHECK: %[[MORE:.*]] = arith.cmpi ult, %[[FOLLOWING]], %[[END]]
  // CHECK: cf.cond_br %[[MORE]], ^[[HEAD]](%[[FOLLOWING]], %[[END]] : i64, i64), ^[[GROUP]](%[[END]] : i64)
  // CHECK: ^[[SCAN]]:
  // CHECK: %[[NEXT:.*]] = arith.addi %[[START]],
  // CHECK: %[[FIRST:.*]] = llvm.getelementptr %arg0[%[[START]]]
  // CHECK: %[[WORDS:.*]] = llvm.load %[[FIRST]] {{.*}} -> vector<8xi64>
  // CHECK: %[[ANY:.*]] = "llvm.intr.vector.reduce.or"(%[[WORDS]])
  // CHECK: %[[NONE:.*]] = arith.cmpi eq, %[[ANY]],
  // CHECK: cf.cond_br %[[NONE]], ^[[GROUP]](%[[NEXT]] : i64), ^[[HEAD]](%[[START]], %[[NEXT]] : i64, i64)
  // CHECK: ^[[REST]]:
  // CHECK: %[[SPAN:.*]] = llvm.mlir.constant(118 : i64)
  // CHECK: %[[TAILDONE:.*]] = arith.cmpi uge, %[[START]], %[[SPAN]]
  // CHECK: cf.cond_br %[[TAILDONE]], ^[[LAST]], ^[[TAIL:bb[0-9]+]]
  // CHECK: ^[[TAIL]]:
  // CHECK: %[[TAILWORDS:.*]] = llvm.load {{.*}} -> vector<6xi64>
  // CHECK: %[[TAILANY:.*]] = "llvm.intr.vector.reduce.or"(%[[TAILWORDS]])
  // CHECK: %[[TAILEMPTY:.*]] = arith.cmpi eq, %[[TAILANY]],
  // CHECK: cf.cond_br %[[TAILEMPTY]], ^[[LAST]], ^[[HEAD]](%{{.*}}, %{{.*}} : i64, i64)
  // CHECK: ^[[DONE]]:
  // CHECK-NOT: schedule.ready
  // CHECK: llvm.return
  llvm.func @merge_7553(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 7553 : i64}
    llvm.return
  }
  // Every add sets its dirty bit at both levels, without testing the leaf.
  // When no word follows the whole groups, they lead straight to the masked
  // last word.
  // CHECK-LABEL: llvm.func @merge_262145(
  // CHECK-NOT: llvm.call
  // CHECK: ^[[LAST:bb[0-9]+]]:
  // CHECK-NEXT: llvm.mlir.constant(4096 : i64)
  // CHECK: ^[[GROUP:bb[0-9]+]](%[[START:.*]]: i64):
  // CHECK: arith.cmpi uge, %[[START]],
  // CHECK: cf.cond_br {{.*}}, ^[[LAST]], ^{{bb[0-9]+}}
  // CHECK: ^{{bb[0-9]+}}(%[[WORD:.*]]: i64, %{{.*}}: i64):
  // CHECK: %[[SOURCE:.*]] = llvm.load
  // CHECK: arith.ori {{.*}}, %[[SOURCE]]
  // CHECK: llvm.store
  // CHECK-NOT: cf.cond_br
  // CHECK: %[[PARENT:.*]] = arith.shrui %[[WORD]],
  // CHECK: llvm.store
  // CHECK-NOT: cf.cond_br
  // CHECK: arith.shrui %[[PARENT]],
  // CHECK: llvm.store
  // CHECK-NEXT: cf.br
  // CHECK: llvm.load {{.*}} -> vector<8xi64>
  // CHECK-NOT: arith.cmpi uge
  // CHECK-NOT: llvm.call
  // CHECK: llvm.return
  llvm.func @merge_262145(%source: !llvm.ptr) {
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 262145 : i64}
    llvm.return
  }
  llvm.func @ready_merge_observe(!llvm.ptr)
  // A merge observes pending scalar updates, and its effects are visible to
  // callbacks and subsequent reads. It is a boundary for ready.region too.
  // OBS-LABEL: llvm.func @merge_observed(
  // OBS: llvm.store
  // OBS: cf.br
  // OBS: llvm.load
  // OBS: cf.cond_br
  // OBS: llvm.call @ready_merge_observe
  // OBS: llvm.store
  // OBS-NOT: schedule.ready
  // OBS: llvm.return
  llvm.func @merge_observed(%source: !llvm.ptr) -> i64 {
    %base = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
    %one = arith.constant 1 : i64
    %eight = arith.constant 8 : i64
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 128 : i64, consume = false}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 128 : i64}
    llvm.call @ready_merge_observe(%base) : (!llvm.ptr) -> ()
    schedule.ready.update @__talos_aot_model_ingress_v1[1], %eight {capacity = 128 : i64, consume = false}
    %result = schedule.ready.read @__talos_aot_model_ingress_v1[1] {capacity = 128 : i64}
    llvm.return %result : i64
  }
}
