// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// IEEE 1800-2023 4.5, 4.6(b), 10.4.2: a dynamic partial NBA may hand the
// entire barrier to runtime. Keep its fixed sibling's compact hot capture,
// then export that sibling's mask, validity, region and dirty-page index at
// the shared boundary. Captured value/unknown planes are never resampled.
// CHECK-LABEL: llvm.func @update.__talos_eval_body_0.__talos_two_state_0(
// CHECK: %[[ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_1
// CHECK: %[[VALUE:.*]] = llvm.getelementptr %[[ACC]][0]
// CHECK: llvm.store {{.*}}, %[[VALUE]]
// CHECK: %[[UNKNOWN:.*]] = llvm.getelementptr %[[ACC]][32]
// CHECK: llvm.store {{.*}}, %[[UNKNOWN]]
// CHECK-NOT: llvm.getelementptr %[[ACC]][64]
// CHECK-NOT: llvm.getelementptr %[[ACC]][96]
// CHECK-NOT: llvm.getelementptr %[[ACC]][100]
// CHECK: llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// CHECK-NOT: llvm.mlir.addressof @__talos_aot_nba_dirty_summary_v1
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @__talos_aot_runtime_nba_commit_v1(
// CHECK-NOT: llvm.call @__talos_eval_export_nba_metadata_v1()
// CHECK: llvm.call @talos_rt_v1_static_nba_commit_roots
// CHECK-LABEL: llvm.func internal @__talos_eval_export_nba_metadata_v1()
// CHECK: llvm.cond_br
// CHECK: %[[PRESENT:.*]] = llvm.icmp "ne"
// CHECK: %[[EXPORT_ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_1
// CHECK: %[[MASK:.*]] = llvm.select %[[PRESENT]], %{{.*}}, %{{.*}} : i1, i64
// CHECK: %[[MASK_ADDR:.*]] = llvm.getelementptr %[[EXPORT_ACC]][64]
// CHECK: llvm.store %[[MASK]], %[[MASK_ADDR]]
// CHECK: %[[VALID:.*]] = llvm.zext %[[PRESENT]] : i1 to i32
// CHECK: %[[VALID_ADDR:.*]] = llvm.getelementptr %[[EXPORT_ACC]][96]
// CHECK: llvm.store %[[VALID]], %[[VALID_ADDR]]
// CHECK: %[[REGION:.*]] = llvm.mlir.constant(2 : i32)
// CHECK: %[[REGION_ADDR:.*]] = llvm.getelementptr %[[EXPORT_ACC]][100]
// CHECK: llvm.store %[[REGION]], %[[REGION_ADDR]]
// CHECK: llvm.store
// CHECK: llvm.return
!b = !simulation.logic<1>
!w8 = !simulation.logic<8>
!r1 = !simulation.ref<!b>
!r8 = !simulation.ref<!w8>
!r16 = !simulation.ref<!simulation.logic<16>>
!r32 = !simulation.ref<!simulation.logic<32>>
!r64 = !simulation.ref<!simulation.logic<64>>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32} {
  simulation.design @eval_dynamic_nba {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "update"
    simulation.storage.decl 0 in 0 : !b design
    simulation.storage.decl 1 in 0 : !simulation.logic<32> design
    simulation.storage.decl 2 in 0 : !simulation.logic<64> design
    simulation.storage.decl 3 in 0 : !w8 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clock = simulation.context.storage %ctx[0] : !r1
      %data = simulation.context.storage %ctx[1] : !r32
      %index = simulation.context.storage %ctx[2] : !r64
      %p = simulation.spawn @update(%ctx, %clock, %data, %index) : !simulation.context, !r1, !r32, !r64 -> !simulation.process
      simulation.return
    }
    simulation.func @update(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clock: !r1 {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !r32 {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %index: !r64 {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clock to ^resume {site = #schedule.continuation<id = 2>} : !r1
    ^resume:
      %low = simulation.ref.load %index : !r64 -> !simulation.logic<64>
      %base = simulation.ref.extract %data from 8 : !r32 -> !r16
      %slice = simulation.ref.dyn_extract %base from %low : (!r16, !simulation.logic<64>) -> !r8
      %value = simulation.logic.constant 165 : i8, 0 : i8 : !w8
      simulation.nba.enqueue %value to %slice : (!w8, !r8) -> ()
      %sibling = simulation.context.storage %ctx[3] : !r8
      %previous = simulation.ref.load %sibling : !r8 -> !w8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !w8
      %next = simulation.logic.binary add %previous, %one : !w8
      simulation.nba.enqueue %next to %sibling : (!w8, !r8) -> ()
      cf.br ^wait
    }
  }
}
