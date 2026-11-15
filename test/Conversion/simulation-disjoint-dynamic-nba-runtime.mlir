// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=PLAN < %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=GUARD < %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=BARRIER < %t.llvm.mlir
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=read},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=read},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.read.llvm.mlir
// RUN: FileCheck %s --check-prefix=READ < %t.read.llvm.mlir

// Empty dynamic slots must bypass stale address/value/unknown loads in both
// commit variants, and each variant clears the slot summary only once the
// last slot is consumed or skipped.
// GUARD-LABEL: llvm.func {{(internal )?}}@__talos_aot_static_nba_commit_v1(
// GUARD: %[[ADDR0:.*]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// GUARD-NEXT: %[[VALID0:.*]] = llvm.load %[[ADDR0]] {{.*}} : !llvm.ptr -> i32
// GUARD-NEXT: %[[ZERO0:.*]] = llvm.mlir.constant(0 : i32)
// GUARD-NEXT: %[[ACTIVE0:.*]] = llvm.icmp "ne" %[[VALID0]], %[[ZERO0]] : i32
// GUARD-NEXT: llvm.cond_br %[[ACTIVE0]], ^[[WORK0:bb[0-9]+]], ^[[NEXT0:bb[0-9]+]]
// GUARD: ^[[WORK0]]:
// GUARD: llvm.mlir.addressof @__talos_eval_nba_offset_
// GUARD: ^[[NEXT0]]:
// GUARD-NEXT: %[[ADDR0B:.*]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// GUARD-NEXT: %[[VALID0B:.*]] = llvm.load %[[ADDR0B]] {{.*}} : !llvm.ptr -> i32
// GUARD-NEXT: %[[ZERO0B:.*]] = llvm.mlir.constant(0 : i32)
// GUARD-NEXT: %[[ACTIVE0B:.*]] = llvm.icmp "ne" %[[VALID0B]], %[[ZERO0B]] : i32
// GUARD-NEXT: llvm.cond_br %[[ACTIVE0B]], ^{{bb[0-9]+}}, ^[[LAST0:bb[0-9]+]]
// GUARD: ^[[LAST0]]:
// GUARD-DAG: %[[CLEAR0:.*]] = llvm.mlir.constant(0 : i32) : i32
// GUARD-DAG: %[[SUMMARY0:.*]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// GUARD-NEXT: llvm.store %[[CLEAR0]], %[[SUMMARY0]]
// This commit stages no accumulator unknown data for a canonical two-state
// variant to zero, so that variant would copy the commit unchanged; there is
// none, and its callers keep the four-state commit.
// GUARD-NOT: @__talos_aot_static_nba_commit_two_state_v1
// GUARD-LABEL: llvm.func {{(internal )?}}@__talos_aot_static_nba_commit_two_state_fast_v1(
// GUARD: %[[ADDR2:.*]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// GUARD-NEXT: %[[VALID2:.*]] = llvm.load %[[ADDR2]] {{.*}} : !llvm.ptr -> i32
// GUARD-NEXT: %[[ZERO2:.*]] = llvm.mlir.constant(0 : i32)
// GUARD-NEXT: %[[ACTIVE2:.*]] = llvm.icmp "ne" %[[VALID2]], %[[ZERO2]] : i32
// GUARD-NEXT: llvm.cond_br %[[ACTIVE2]], ^[[WORK2:bb[0-9]+]], ^[[NEXT2:bb[0-9]+]]
// GUARD: ^[[WORK2]]:
// GUARD: llvm.mlir.addressof @__talos_eval_nba_offset_
// GUARD: ^[[NEXT2]]:
// GUARD-NEXT: %[[ADDR2B:.*]] = llvm.mlir.addressof @__talos_eval_nba_valid_
// GUARD-NEXT: %[[VALID2B:.*]] = llvm.load %[[ADDR2B]] {{.*}} : !llvm.ptr -> i32
// GUARD-NEXT: %[[ZERO2B:.*]] = llvm.mlir.constant(0 : i32)
// GUARD-NEXT: %[[ACTIVE2B:.*]] = llvm.icmp "ne" %[[VALID2B]], %[[ZERO2B]] : i32
// GUARD-NEXT: llvm.cond_br %[[ACTIVE2B]], ^{{bb[0-9]+}}, ^[[LAST2:bb[0-9]+]]
// GUARD: ^[[LAST2]]:
// GUARD-DAG: %[[CLEAR2:.*]] = llvm.mlir.constant(0 : i32) : i32
// GUARD-DAG: %[[SUMMARY2:.*]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// GUARD-NEXT: llvm.store %[[CLEAR2]], %[[SUMMARY2]]
// Read-only reflection admits cbValueChange, which runs after every value
// change (IEEE 1800-2017 38.36.1), so an intermediate NBA value is observable
// and neither lane may take a one-entry latch. The generated queue keeps both
// writes; its count joins the dispatcher's empty-barrier test.
// READ-NOT: llvm.mlir.global internal @__talos_eval_nba_valid_
// READ: llvm.mlir.global internal @__talos_eval_ordered_nba_queue_v1
// READ-NOT: llvm.mlir.global internal @__talos_eval_nba_valid_
// READ-LABEL: llvm.func @__talos_eval_dispatch_v1(
// READ: llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// READ: %[[D0:.*]] = llvm.load {{.*}} : !llvm.ptr -> i64
// READ: llvm.mlir.addressof @__talos_eval_ordered_nba_queue_v1
// READ: %[[COUNT:.*]] = llvm.load {{.*}} : !llvm.ptr -> i32
// READ: %[[WIDE:.*]] = llvm.zext %[[COUNT]] : i32 to i64
// READ: %[[PENDING:.*]] = llvm.or %[[D0]], %[[WIDE]] : i64
// READ: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64)
// READ: %[[EMPTY:.*]] = llvm.icmp "eq" %[[PENDING]], %[[ZERO]] : i64
// READ: llvm.cond_br %[[EMPTY]]
// Without VPI, nothing watches the root: two independent lanes keep one
// latch each and must preserve both writes, including when their indices
// alias. Negative, out-of-range and unknown indices must write none.
// PLAN-COUNT-2: llvm.mlir.global internal @__talos_eval_nba_valid_
// PLAN-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// PLAN: llvm.call @talos_rt_v1_scheduler_prepare_periodic_aot

// The dispatcher's empty-barrier test must see BOTH dynamic slots. Neither
// slot sets fixed dirty bits: each staging site sets the one summary word the
// test reads (the GUARD checks pin where each commit variant clears it).
// BARRIER-LABEL: llvm.func @update.__talos_eval_body_0(
// BARRIER: %[[SLOT0:.*]] = llvm.mlir.addressof @__talos_eval_nba_valid_0
// BARRIER-NEXT: llvm.store %[[BIT0:.*]], %[[SLOT0]] {{.*}} : i32, !llvm.ptr
// BARRIER-NEXT: %[[SUM0:.*]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// BARRIER-NEXT: %[[OLD0:.*]] = llvm.load %[[SUM0]] {{.*}} : !llvm.ptr -> i32
// BARRIER-NEXT: %[[NEW0:.*]] = llvm.or %[[OLD0]], %[[BIT0]] : i32
// BARRIER-NEXT: llvm.store %[[NEW0]], %[[SUM0]]
// BARRIER: %[[SLOT1:.*]] = llvm.mlir.addressof @__talos_eval_nba_valid_1
// BARRIER-NEXT: llvm.store %[[BIT1:.*]], %[[SLOT1]] {{.*}} : i32, !llvm.ptr
// BARRIER-NEXT: %[[SUM1:.*]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// BARRIER-NEXT: %[[OLD1:.*]] = llvm.load %[[SUM1]] {{.*}} : !llvm.ptr -> i32
// BARRIER-NEXT: %[[NEW1:.*]] = llvm.or %[[OLD1]], %[[BIT1]] : i32
// BARRIER-NEXT: llvm.store %[[NEW1]], %[[SUM1]]
// BARRIER-LABEL: llvm.func @__talos_eval_dispatch_v1(
// BARRIER: llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// BARRIER: %[[D0:.*]] = llvm.load {{.*}} : !llvm.ptr -> i64
// BARRIER-NEXT: %[[A0:.*]] = llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// BARRIER-NEXT: %[[V0:.*]] = llvm.load %[[A0]] {{.*}} : !llvm.ptr -> i32
// BARRIER-NEXT: %[[Z0:.*]] = llvm.zext %[[V0]] : i32 to i64
// BARRIER-NEXT: %[[Q0:.*]] = llvm.or %[[D0]], %[[Z0]] : i64
// BARRIER-NEXT: %[[ZERO0:.*]] = llvm.mlir.constant(0 : i64)
// BARRIER-NEXT: %[[EMPTY0:.*]] = llvm.icmp "eq" %[[Q0]], %[[ZERO0]] : i64
// BARRIER-NEXT: %[[OK0:.*]] = llvm.mlir.constant(0 : i32)
// BARRIER-NEXT: llvm.cond_br %[[EMPTY0]], ^[[DONE0:bb[0-9]+]](%[[OK0]] : i32), ^[[COMMIT0:bb[0-9]+]]
// BARRIER-NEXT: ^[[COMMIT0]]:
// BARRIER: ^[[DONE0]](%[[STATUS0:.*]]: i32):
// BARRIER-NEXT: %[[EXIT0:.*]] = llvm.call @__talos_eval_route_promotion_boundary_v1(%[[STATUS0]]) : (i32) -> i32
// BARRIER-NEXT: llvm.return %[[EXIT0]] : i32

!words = !simulation.unpacked_array<0 : 31 x !simulation.logic<32>>

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @eval_disjoint_dynamic_nba_runtime {
    simulation.scope.decl 0 hierarchy "eval_disjoint_dynamic_nba_runtime"
    simulation.code_unit.decl 1 in 0 root_initializer
        hierarchy "eval_disjoint_dynamic_nba_runtime.root"
    simulation.code_unit.decl 2 in 0 always
        hierarchy "eval_disjoint_dynamic_nba_runtime.clock_process"
    simulation.code_unit.decl 3 in 0 always
        hierarchy "eval_disjoint_dynamic_nba_runtime.update"
    simulation.code_unit.decl 4 in 0 initial hierarchy "eval_disjoint_dynamic_nba_runtime.check"
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design hierarchy "eval_disjoint_dynamic_nba_runtime.clock"
    simulation.storage.decl 1 in 0 : !words design hierarchy "eval_disjoint_dynamic_nba_runtime.data"
    simulation.storage.decl 2 in 0 : !simulation.logic<64> design hierarchy "eval_disjoint_dynamic_nba_runtime.index"
    simulation.storage.decl 3 in 0 : !simulation.logic<64> design hierarchy "eval_disjoint_dynamic_nba_runtime.other_index"

    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clock = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<1>>
      %data = simulation.context.storage %ctx[1] :
          !simulation.ref<!words>
      %index = simulation.context.storage %ctx[2] :
          !simulation.ref<!simulation.logic<64>>
      %otherIndex = simulation.context.storage %ctx[3] :
          !simulation.ref<!simulation.logic<64>>
      %zeroClock = simulation.logic.constant 0 : i1, 0 : i1 : !simulation.logic<1>
      simulation.ref.store %zeroClock to %clock : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      %zeroIndex = simulation.logic.constant 0 : i64, 0 : i64 : !simulation.logic<64>
      %oneIndex = simulation.logic.constant 1 : i64, 0 : i64 : !simulation.logic<64>
      simulation.ref.store %zeroIndex to %index : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      simulation.ref.store %oneIndex to %otherIndex : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      %zeroWord = simulation.logic.constant 0 : i32, 0 : i32 : !simulation.logic<32>
      %word0 = simulation.ref.subelement %data[[0]] : !simulation.ref<!words> -> !simulation.ref<!simulation.logic<32>>
      %word1 = simulation.ref.subelement %data[[1]] : !simulation.ref<!words> -> !simulation.ref<!simulation.logic<32>>
      simulation.ref.store %zeroWord to %word0 : !simulation.logic<32>, !simulation.ref<!simulation.logic<32>>
      simulation.ref.store %zeroWord to %word1 : !simulation.logic<32>, !simulation.ref<!simulation.logic<32>>
      %check = simulation.spawn @check(%ctx, %data, %index, %otherIndex) :
          !simulation.context, !simulation.ref<!words>,
          !simulation.ref<!simulation.logic<64>>, !simulation.ref<!simulation.logic<64>> -> !simulation.process
      %c = simulation.spawn @clock(%ctx, %clock) :
          !simulation.context, !simulation.ref<!simulation.logic<1>>
          -> !simulation.process
      %p = simulation.spawn @update(%ctx, %clock, %data, %index, %otherIndex) :
          !simulation.context, !simulation.ref<!simulation.logic<1>>,
          !simulation.ref<!words>,
          !simulation.ref<!simulation.logic<64>>,
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
             simulation.descriptor_id = 2 : i64},
        %otherIndex: !simulation.ref<!simulation.logic<64>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 3 : i64})
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
      %lo = simulation.ref.extract %element from 0 :
          !simulation.ref<!simulation.logic<32>> -> !simulation.ref<!simulation.logic<8>>
      %otherLow = simulation.ref.load %otherIndex :
          !simulation.ref<!simulation.logic<64>> -> !simulation.logic<64>
      %otherElement = simulation.ref.array_element %data[%otherLow] :
          (!simulation.ref<!words>, !simulation.logic<64>) ->
          !simulation.ref<!simulation.logic<32>>
      %hi = simulation.ref.extract %otherElement from 16 :
          !simulation.ref<!simulation.logic<32>> -> !simulation.ref<!simulation.logic<8>>
      %value = simulation.logic.constant 85 : i8, 0 : i8 : !simulation.logic<8>
      simulation.nba.enqueue %value to %lo :
          (!simulation.logic<8>, !simulation.ref<!simulation.logic<8>>) -> ()
      simulation.nba.enqueue %value to %hi :
          (!simulation.logic<8>, !simulation.ref<!simulation.logic<8>>) -> ()
      cf.br ^wait
    }
    simulation.func @check(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %data: !simulation.ref<!words> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64},
        %index: !simulation.ref<!simulation.logic<64>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64},
        %otherIndex: !simulation.ref<!simulation.logic<64>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %delay = simulation.time.constant 3
      simulation.suspend.delay %delay to ^separate
    ^separate:
      %word0 = simulation.ref.subelement %data[[0]] : !simulation.ref<!words> -> !simulation.ref<!simulation.logic<32>>
      %word1 = simulation.ref.subelement %data[[1]] : !simulation.ref<!words> -> !simulation.ref<!simulation.logic<32>>
      %first0 = simulation.ref.load %word0 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      %first1 = simulation.ref.load %word1 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      %format = simulation.bytes.constant "%08h %08h"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%format, %first0, %first1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<32>, !simulation.logic<32>
      %invalid = simulation.logic.constant 32 : i64, 0 : i64 : !simulation.logic<64>
      %negative = simulation.logic.constant -1 : i64, 0 : i64 : !simulation.logic<64>
      simulation.ref.store %invalid to %index : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      simulation.ref.store %negative to %otherIndex : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      %two = simulation.time.constant 2
      simulation.suspend.delay %two to ^outside
    ^outside:
      %outside0 = simulation.ref.load %word0 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      %outside1 = simulation.ref.load %word1 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      simulation.display %ctx to %stdout(%format, %outside0, %outside1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<32>, !simulation.logic<32>
      %unknown = simulation.logic.constant 0 : i64, -1 : i64 : !simulation.logic<64>
      simulation.ref.store %unknown to %index : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      simulation.ref.store %unknown to %otherIndex : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      simulation.suspend.delay %two to ^unknown
    ^unknown:
      %unknown0 = simulation.ref.load %word0 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      %unknown1 = simulation.ref.load %word1 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      simulation.display %ctx to %stdout(%format, %unknown0, %unknown1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<32>, !simulation.logic<32>
      %zero = simulation.logic.constant 0 : i64, 0 : i64 : !simulation.logic<64>
      simulation.ref.store %zero to %index : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      simulation.ref.store %zero to %otherIndex : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
      simulation.suspend.delay %two to ^same
    ^same:
      %same0 = simulation.ref.load %word0 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      %same1 = simulation.ref.load %word1 : !simulation.ref<!simulation.logic<32>> -> !simulation.logic<32>
      simulation.display %ctx to %stdout(%format, %same0, %same1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<32>, !simulation.logic<32>
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
