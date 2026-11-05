// RUN: talos-opt %s \
// RUN:   --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep))' \
// RUN:   -o %t.planned.mlir
// RUN: talos-opt %t.planned.mlir \
// RUN:   --convert-talos-sim-processes-to-llvm-coroutines \
// RUN:   -o %t.llvm.mlir
// RUN: FileCheck %s < %t.llvm.mlir

// Feed preplanned Simulation IR to only the coroutine conversion pass. The
// array element of a captured root is addressable, and no event control
// watches the root, so its one semantic site takes the periodic latch.
!words = !simulation.unpacked_array<0 : 31 x !simulation.logic<32>>
!wide = !simulation.unpacked_array<0 : 3 x !simulation.logic<96>>

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @eval_wide_dynamic_nba {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer
        hierarchy "eval_wide_dynamic_nba.root"
    simulation.code_unit.decl 2 in 0 always
        hierarchy "eval_wide_dynamic_nba.clock"
    simulation.code_unit.decl 3 in 0 always
        hierarchy "eval_wide_dynamic_nba.update"
    simulation.code_unit.decl 4 in 0 always
        hierarchy "eval_wide_dynamic_nba.update_wide"
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
    simulation.storage.decl 1 in 0 : !words design
    simulation.storage.decl 2 in 0 : !simulation.logic<64> design
    simulation.storage.decl 3 in 0 : !wide design

    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clock = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<1>>
      %data = simulation.context.storage %ctx[1] :
          !simulation.ref<!words>
      %index = simulation.context.storage %ctx[2] :
          !simulation.ref<!simulation.logic<64>>
      %c = simulation.spawn @clock(%ctx, %clock) :
          !simulation.context, !simulation.ref<!simulation.logic<1>>
          -> !simulation.process
      %p = simulation.spawn @update(%ctx, %clock, %data, %index) :
          !simulation.context, !simulation.ref<!simulation.logic<1>>,
          !simulation.ref<!words>,
          !simulation.ref<!simulation.logic<64>> -> !simulation.process
      %wide = simulation.context.storage %ctx[3] :
          !simulation.ref<!wide>
      %w = simulation.spawn @update_wide(%ctx, %clock, %wide, %index) :
          !simulation.context, !simulation.ref<!simulation.logic<1>>,
          !simulation.ref<!wide>,
          !simulation.ref<!simulation.logic<64>> -> !simulation.process
      simulation.return
    }

    simulation.func @clock(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^toggle
          {site = #schedule.continuation<id = 1>,
           timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clock :
          !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %new = simulation.logic.unary bit_not %old :
          (!simulation.logic<1>) -> !simulation.logic<1>
      simulation.ref.store %new to %clock : !simulation.logic<1>,
          !simulation.ref<!simulation.logic<1>>
      cf.br ^wait
    }

    simulation.func @update(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64},
        %data: !simulation.ref<!words>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 1 : i64},
        %index: !simulation.ref<!simulation.logic<64>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 2 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clock to ^resume
          {site = #schedule.continuation<id = 2>} :
          !simulation.ref<!simulation.logic<1>>
    ^resume:
      %low = simulation.ref.load %index :
          !simulation.ref<!simulation.logic<64>> -> !simulation.logic<64>
      %element = simulation.ref.array_element %data[%low] :
          (!simulation.ref<!words>, !simulation.logic<64>) ->
          !simulation.ref<!simulation.logic<32>>
      %value = simulation.logic.constant -1515870811 : i32, 0 : i32 :
          !simulation.logic<32>
      simulation.nba.enqueue %value to %element :
          (!simulation.logic<32>,
           !simulation.ref<!simulation.logic<32>>) -> ()
      cf.br ^wait
    }

    // A 96-bit element stages two 64-bit chunk slots: each chunk stores its
    // own valid word, and the site sets the summary once.
    simulation.func @update_wide(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64},
        %data: !simulation.ref<!wide>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 3 : i64},
        %index: !simulation.ref<!simulation.logic<64>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 2 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clock to ^resume
          {site = #schedule.continuation<id = 3>} :
          !simulation.ref<!simulation.logic<1>>
    ^resume:
      %low = simulation.ref.load %index :
          !simulation.ref<!simulation.logic<64>> -> !simulation.logic<64>
      %element = simulation.ref.array_element %data[%low] :
          (!simulation.ref<!wide>, !simulation.logic<64>) ->
          !simulation.ref<!simulation.logic<96>>
      %value = simulation.logic.constant -1 : i96, 0 : i96 :
          !simulation.logic<96>
      simulation.nba.enqueue %value to %element :
          (!simulation.logic<96>,
           !simulation.ref<!simulation.logic<96>>) -> ()
      cf.br ^wait
    }
  }
}

// Each staging site also ORs its valid bit into one summary word; the
// coordinator's quiescence test reads only that word, and the commit clears it
// once the last slot is consumed or found empty.
// CHECK-LABEL: module attributes
// CHECK-NOT: llvm.mlir.global internal @__talos_eval_ordered_nba_queue_v1
// CHECK-DAG: llvm.mlir.global internal @__talos_eval_nba_dynamic_pending_v1(0 : i32) {{.*}} : i32
// CHECK-DAG: llvm.mlir.global internal @__talos_eval_nba_valid_0() {{.*}} : i32
// CHECK-NOT: llvm.mlir.global internal @__talos_eval_ordered_nba_queue_v1
// CHECK-LABEL: llvm.func @update.__talos_eval_body_0(
// CHECK-NOT: llvm.call @talos_rt_v1_scheduler_{{(static_)?}}nba
// CHECK: %[[SLOT:.+]] = llvm.mlir.addressof @__talos_eval_nba_valid_0
// CHECK-NEXT: llvm.store %[[VALID:.+]], %[[SLOT]]
// CHECK-NEXT: %[[SUMMARY:.+]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// CHECK-NEXT: %[[PRIOR:.+]] = llvm.load %[[SUMMARY]]
// CHECK-NEXT: %[[MARKED:.+]] = llvm.or %[[PRIOR]], %[[VALID]]
// CHECK-NEXT: llvm.store %[[MARKED]], %[[SUMMARY]]
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @update_wide.__talos_eval_body_0(
// CHECK: %[[CHUNK0:.+]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// CHECK-NEXT: llvm.store %[[WIDEVALID:.+]], %[[CHUNK0]]
// CHECK-NOT: @__talos_eval_nba_dynamic_pending_v1
// CHECK: %[[CHUNK1:.+]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// CHECK-NEXT: llvm.store %[[WIDEVALID]], %[[CHUNK1]]
// CHECK-NEXT: %[[WIDESUMMARY:.+]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// CHECK-NEXT: %[[WIDEPRIOR:.+]] = llvm.load %[[WIDESUMMARY]]
// CHECK-NEXT: %[[WIDEMARKED:.+]] = llvm.or %[[WIDEPRIOR]], %[[WIDEVALID]]
// CHECK-NEXT: llvm.store %[[WIDEMARKED]], %[[WIDESUMMARY]]
// CHECK-NOT: @__talos_eval_nba_dynamic_pending_v1
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK: llvm.call @__talos_eval_dispatch_v1
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK-NOT: @__talos_eval_nba_valid_
// CHECK: %[[DIRTY:.+]] = llvm.load %{{.+}} : !llvm.ptr -> i64
// CHECK-NEXT: %[[SUMMARY:.+]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// CHECK-NEXT: %[[PENDING:.+]] = llvm.load %[[SUMMARY]] {{.*}} -> i32
// CHECK-NEXT: %[[WIDE:.+]] = llvm.zext %[[PENDING]] : i32 to i64
// CHECK-NEXT: llvm.or %[[DIRTY]], %[[WIDE]] : i64
// CHECK-NOT: @__talos_eval_nba_valid_
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK-COUNT-2: llvm.mlir.addressof @__talos_eval_nba_valid_
// CHECK-NOT: @__talos_eval_nba_dynamic_pending_v1
// CHECK: %[[SLOT:.+]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// CHECK: llvm.cond_br %{{.+}}, ^[[CONSUME:bb[0-9]+]], ^[[NEXT:bb[0-9]+]]
// CHECK: ^[[NEXT]]:
// CHECK-NEXT: %[[ZERO:.+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[SUMMARY:.+]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// CHECK-NEXT: llvm.store %[[ZERO]], %[[SUMMARY]]
// CHECK: llvm.store %{{.+}}, %[[SLOT]] {{.*}} : i32, !llvm.ptr
// CHECK: llvm.br ^[[NEXT]]
