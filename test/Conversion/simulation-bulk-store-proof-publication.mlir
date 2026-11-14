// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{schedule.eval.force_two_state}"' | talos-opt --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s --check-prefix=FILL

// A packed value wider than 64 bits writes its X/Z plane with a direct bulk
// copy. Like a scalar store, the copy must report each 64-bit chunk's exact
// X/Z change to the proofs covering its destination (IEEE 1800-2023 6.3.1);
// otherwise a valid two-state proof survives X/Z arriving in the copied
// bytes. The change is the destination's bytes before the copy xor the
// copied bytes, published just before the copy. Up to 64 bytes publish per
// chunk at constant offsets (compile-time windows); longer copies publish
// whole words in a loop, then their tail.

// 80-bit destination at byte 11: chunks [88, 152) and [152, 168).
// CHECK-LABEL: llvm.func @copy.__talos_eval_body_0(
// CHECK: %[[UNKNOWN:.*]] = llvm.mlir.addressof @__talos_state_unknown
// CHECK: llvm.getelementptr %{{.*}}[11]
// CHECK: %[[DST:.*]] = llvm.getelementptr %[[UNKNOWN]][11]
// CHECK: %[[OLD:.*]] = llvm.load %{{.*}} -> i64
// CHECK: %[[NEW:.*]] = llvm.load %{{.*}} -> i64
// CHECK: %[[DELTA:.*]] = llvm.xor %[[OLD]], %[[NEW]] : i64
// CHECK: llvm.cond_br
// CHECK: llvm.mlir.addressof @__talos_eval_promotion_window_88_v1
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_window_v1(%{{.*}}, %{{.*}}, %[[DELTA]], %[[NEW]])
// CHECK: llvm.load %{{.*}} -> i16
// CHECK: llvm.load %{{.*}} -> i16
// CHECK: llvm.mlir.addressof @__talos_eval_promotion_window_152_v1
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_window_v1
// CHECK: "llvm.intr.memcpy"(%[[DST]],
// 600-bit destination at byte 96: nine words in a loop, then a 24-bit tail.
// CHECK: %[[WIDE_UNKNOWN:.*]] = llvm.mlir.addressof @__talos_state_unknown
// CHECK: llvm.getelementptr %{{.*}}[96]
// CHECK: %[[WIDE:.*]] = llvm.getelementptr %[[WIDE_UNKNOWN]][96]
// CHECK: llvm.icmp "ult" %{{.*}}, %{{.*}} : i64
// CHECK: llvm.load %{{.*}} -> i64
// CHECK: llvm.load %{{.*}} -> i64
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_unknown_v1
// CHECK: llvm.load %{{.*}} -> i24
// CHECK: llvm.mlir.addressof @__talos_eval_promotion_window_1344_v1
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_window_v1
// CHECK: "llvm.intr.memcpy"(%[[WIDE]],
// The proven two-state copy keeps the X/Z plane and publishes nothing.
// CHECK-LABEL: llvm.func @copy.__talos_eval_body_0.__talos_two_state_0(
// CHECK-NOT: __talos_eval_promotion_publish
// CHECK: llvm.return

// A forced two-state build clears the whole 171-byte X/Z plane with a fill
// when it prepares the schedule. Its new bytes are the splatted fill byte;
// whole words are published in a loop, then the 24-bit tail, before the fill.
// FILL-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// FILL: %[[PLANE:.*]] = llvm.mlir.addressof @__talos_state_unknown
// FILL-NEXT: %[[FILL:.*]] = llvm.mlir.constant(0 : i8)
// FILL-NEXT: %[[BYTES:.*]] = llvm.mlir.constant(171 : i64)
// FILL: llvm.icmp "ult"
// FILL: %[[OLD:.*]] = llvm.load %{{.*}} -> i64
// FILL: %[[WIDE:.*]] = llvm.zext %[[FILL]] : i8 to i64
// FILL: %[[ONES:.*]] = llvm.mlir.constant(72340172838076673 : i64)
// FILL: %[[NEW:.*]] = llvm.mul %[[WIDE]], %[[ONES]] : i64
// FILL: %[[DELTA:.*]] = llvm.xor %[[OLD]], %[[NEW]] : i64
// FILL: llvm.call preserve_mostcc @__talos_eval_promotion_publish_unknown_v1(%{{.*}}, %[[DELTA]], %[[NEW]])
// FILL: llvm.load %{{.*}} -> i24
// FILL: llvm.mlir.addressof @__talos_eval_promotion_window_1344_v1
// FILL: llvm.call preserve_mostcc @__talos_eval_promotion_publish_window_v1
// FILL: "llvm.intr.memset"(%[[PLANE]], %[[FILL]], %[[BYTES]])

!record = !simulation.packed_struct<[
  #simulation.field<name = "hi", type = !simulation.logic<8>, ordinal = 0, packedOffset = 72>,
  #simulation.field<name = "lo", type = !simulation.logic<72>, ordinal = 1, packedOffset = 0>
]>
!wide = !simulation.packed_struct<[
  #simulation.field<name = "hi", type = !simulation.logic<88>, ordinal = 0, packedOffset = 512>,
  #simulation.field<name = "lo", type = !simulation.logic<512>, ordinal = 1, packedOffset = 0>
]>
module attributes {
  native.closed_executable,
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "aarch64-unknown-linux-gnu",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @bulk {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
    simulation.storage.decl 1 in 0 : !record design
    simulation.storage.decl 2 in 0 : !record design
    simulation.storage.decl 3 in 0 : !wide design
    simulation.storage.decl 4 in 0 : !wide design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "copy"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %levels = arith.constant 0 : i64
      %scope = simulation.bytes.constant ""
      simulation.dump.vars %ctx, %levels, %scope :
          (!simulation.context, i64, !simulation.bytes) -> ()
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<1>>
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %w = simulation.spawn @copy(%ctx, %clk) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }
    simulation.func @clock(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^toggle
    ^toggle:
      %old = simulation.ref.load %clk : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %next = simulation.logic.unary bit_not %old : (!simulation.logic<1>) -> !simulation.logic<1>
      simulation.ref.store %next to %clk : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      cf.br ^wait
    }
    simulation.func @copy(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %source = simulation.context.storage %ctx[1] : !simulation.ref<!record>
      %destination = simulation.context.storage %ctx[2] : !simulation.ref<!record>
      %value = simulation.ref.load %source : !simulation.ref<!record> -> !record
      simulation.ref.store %value to %destination : !record, !simulation.ref<!record>
      %wide_source = simulation.context.storage %ctx[3] : !simulation.ref<!wide>
      %wide_destination = simulation.context.storage %ctx[4] : !simulation.ref<!wide>
      %wide = simulation.ref.load %wide_source : !simulation.ref<!wide> -> !wide
      simulation.ref.store %wide to %wide_destination : !wide, !simulation.ref<!wide>
      cf.br ^wait
    }
  }
}
