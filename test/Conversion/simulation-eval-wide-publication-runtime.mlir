// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' --mlir-print-ir-after=materialize-native-processes -o %t.llvm.mlir 2> %t.materialized.mlir
// RUN: FileCheck %s --check-prefix=PLAN < %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=SLICE < %t.materialized.mlir

// A 65-bit blocking copy must publish both words without leaving generated
// evaluation. A high-word-only change wakes change observers, not vector
// posedge observers: vector edges use only the LSB (IEEE 1800-2023 9.4.2).
// Shared helpers retain monitor-aware runtime output; only their private
// generated copies may use snapshot output. Warnings are not dropped.
// The store's transition carries its planes as values. AOT planning publishes
// it as one transition per 64-bit slice of the root, a shift and truncation
// of each plane, with no stack snapshot: the low slice, bits 0-63, wakes the
// posedge observer (ingress bit 4) on its LSB and the change observer (bit 2)
// on any change; the high slice, bit 64, wakes only the change observer.
// SLICE-LABEL: func.func private @publish.__talos_eval_body_0(
// SLICE-NOT: llvm.alloca
// SLICE: %[[OLD_WORDS:[0-9]+]] = schedule.state.load @__talos_state_value[1] {alignment = 1 : i64} : i72
// SLICE-NEXT: %[[OLD:[0-9]+]] = llvm.trunc %[[OLD_WORDS]] : i72 to i65
// SLICE-NEXT: %[[OLD_UNKNOWN_WORDS:[0-9]+]] = schedule.state.load @__talos_state_unknown[1] {alignment = 1 : i64} : i72
// SLICE-NEXT: %[[OLD_UNKNOWN:[0-9]+]] = llvm.trunc %[[OLD_UNKNOWN_WORDS]] : i72 to i65
// SLICE: %[[NEW:[0-9]+]] = arith.select %{{[0-9]+}}, %{{[^ ]+}}, %[[OLD]] : i65
// SLICE: %[[NEW_UNKNOWN:[0-9]+]] = arith.select %{{[0-9]+}}, %{{[^ ]+}}, %[[OLD_UNKNOWN]] : i65
// SLICE-NOT: llvm.alloca
// SLICE: %[[OLD_LOW:[0-9]+]] = llvm.trunc %[[OLD]] : i65 to i64
// SLICE-NEXT: %[[OLD_UNKNOWN_LOW:[0-9]+]] = llvm.trunc %[[OLD_UNKNOWN]] : i65 to i64
// SLICE-NEXT: %[[NEW_LOW:[0-9]+]] = llvm.trunc %[[NEW]] : i65 to i64
// SLICE-NEXT: %[[NEW_UNKNOWN_LOW:[0-9]+]] = llvm.trunc %[[NEW_UNKNOWN]] : i65 to i64
// SLICE-NEXT: %[[LOW_VALUE_CHANGES:[0-9]+]] = arith.xori %[[OLD_LOW]], %[[NEW_LOW]] : i64
// SLICE-NEXT: %[[LOW_UNKNOWN_CHANGES:[0-9]+]] = arith.xori %[[OLD_UNKNOWN_LOW]], %[[NEW_UNKNOWN_LOW]] : i64
// SLICE-NEXT: %[[LOW_CHANGES:[0-9]+]] = arith.ori %[[LOW_VALUE_CHANGES]], %[[LOW_UNKNOWN_CHANGES]] : i64
// SLICE: %[[LSB:[0-9]+]] = llvm.mlir.constant(1 : i64) : i64
// SLICE-NEXT: %[[LSB_POSEDGE:[0-9]+]] = arith.andi %{{[0-9]+}}, %[[LSB]] : i64
// SLICE-NEXT: %[[POSEDGES:[0-9]+]] = arith.ori %{{[0-9]+}}, %[[LSB_POSEDGE]] : i64
// SLICE-NEXT: %[[NO_POSEDGE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[POSEDGE:[0-9]+]] = arith.cmpi ne, %[[POSEDGES]], %[[NO_POSEDGE]] : i64
// SLICE-NEXT: %[[POSEDGE_OBSERVER:[0-9]+]] = llvm.mlir.constant(4 : i64) : i64
// SLICE-NEXT: %[[NO_POSEDGE_WAKE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[POSEDGE_WAKE:[0-9]+]] = arith.select %[[POSEDGE]], %[[POSEDGE_OBSERVER]], %[[NO_POSEDGE_WAKE]] : i64
// SLICE-NEXT: schedule.ready.update @__talos_aot_model_ingress_v1[0], %[[POSEDGE_WAKE]] {capacity = 64 : i64, consume = false}
// SLICE-NEXT: %[[NO_LOW_CHANGE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[LOW_MASK:[0-9]+]] = llvm.mlir.constant(-1 : i64) : i64
// SLICE-NEXT: %[[LOW_SLICE_CHANGES:[0-9]+]] = arith.andi %[[LOW_CHANGES]], %[[LOW_MASK]] : i64
// SLICE-NEXT: %[[LOW_ANY:[0-9]+]] = arith.ori %[[NO_LOW_CHANGE]], %[[LOW_SLICE_CHANGES]] : i64
// SLICE-NEXT: %[[LOW_NONE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[LOW_CHANGED:[0-9]+]] = arith.cmpi ne, %[[LOW_ANY]], %[[LOW_NONE]] : i64
// SLICE-NEXT: %[[CHANGE_OBSERVER:[0-9]+]] = llvm.mlir.constant(2 : i64) : i64
// SLICE-NEXT: %[[NO_LOW_WAKE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[LOW_WAKE:[0-9]+]] = arith.select %[[LOW_CHANGED]], %[[CHANGE_OBSERVER]], %[[NO_LOW_WAKE]] : i64
// SLICE-NEXT: schedule.ready.update @__talos_aot_model_ingress_v1[0], %[[LOW_WAKE]] {capacity = 64 : i64, consume = false}
// SLICE-NEXT: %{{[0-9]+}} = llvm.mlir.constant(64 : i64) : i64
// SLICE-NEXT: %[[OLD_SHIFT:[0-9]+]] = llvm.mlir.constant(64 : i65) : i65
// SLICE-NEXT: %[[OLD_HIGH_PLANE:[0-9]+]] = llvm.lshr %[[OLD]], %[[OLD_SHIFT]] : i65
// SLICE-NEXT: %[[OLD_HIGH:[0-9]+]] = llvm.trunc %[[OLD_HIGH_PLANE]] : i65 to i64
// SLICE-NEXT: %[[OLD_UNKNOWN_SHIFT:[0-9]+]] = llvm.mlir.constant(64 : i65) : i65
// SLICE-NEXT: %[[OLD_UNKNOWN_HIGH_PLANE:[0-9]+]] = llvm.lshr %[[OLD_UNKNOWN]], %[[OLD_UNKNOWN_SHIFT]] : i65
// SLICE-NEXT: %[[OLD_UNKNOWN_HIGH:[0-9]+]] = llvm.trunc %[[OLD_UNKNOWN_HIGH_PLANE]] : i65 to i64
// SLICE-NEXT: %[[NEW_SHIFT:[0-9]+]] = llvm.mlir.constant(64 : i65) : i65
// SLICE-NEXT: %[[NEW_HIGH_PLANE:[0-9]+]] = llvm.lshr %[[NEW]], %[[NEW_SHIFT]] : i65
// SLICE-NEXT: %[[NEW_HIGH:[0-9]+]] = llvm.trunc %[[NEW_HIGH_PLANE]] : i65 to i64
// SLICE-NEXT: %[[NEW_UNKNOWN_SHIFT:[0-9]+]] = llvm.mlir.constant(64 : i65) : i65
// SLICE-NEXT: %[[NEW_UNKNOWN_HIGH_PLANE:[0-9]+]] = llvm.lshr %[[NEW_UNKNOWN]], %[[NEW_UNKNOWN_SHIFT]] : i65
// SLICE-NEXT: %[[NEW_UNKNOWN_HIGH:[0-9]+]] = llvm.trunc %[[NEW_UNKNOWN_HIGH_PLANE]] : i65 to i64
// SLICE-NEXT: %[[HIGH_VALUE_CHANGES:[0-9]+]] = arith.xori %[[OLD_HIGH]], %[[NEW_HIGH]] : i64
// SLICE-NEXT: %[[HIGH_UNKNOWN_CHANGES:[0-9]+]] = arith.xori %[[OLD_UNKNOWN_HIGH]], %[[NEW_UNKNOWN_HIGH]] : i64
// SLICE-NEXT: %[[HIGH_CHANGES:[0-9]+]] = arith.ori %[[HIGH_VALUE_CHANGES]], %[[HIGH_UNKNOWN_CHANGES]] : i64
// SLICE-NEXT: %{{[0-9]+}} = llvm.mlir.constant(1 : i64) : i64
// SLICE-NEXT: %[[NO_HIGH_CHANGE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[HIGH_MASK:[0-9]+]] = llvm.mlir.constant(1 : i64) : i64
// SLICE-NEXT: %[[HIGH_SLICE_CHANGES:[0-9]+]] = arith.andi %[[HIGH_CHANGES]], %[[HIGH_MASK]] : i64
// SLICE-NEXT: %[[HIGH_ANY:[0-9]+]] = arith.ori %[[NO_HIGH_CHANGE]], %[[HIGH_SLICE_CHANGES]] : i64
// SLICE-NEXT: %[[HIGH_NONE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[HIGH_CHANGED:[0-9]+]] = arith.cmpi ne, %[[HIGH_ANY]], %[[HIGH_NONE]] : i64
// SLICE-NEXT: %[[HIGH_CHANGE_OBSERVER:[0-9]+]] = llvm.mlir.constant(2 : i64) : i64
// SLICE-NEXT: %[[NO_HIGH_WAKE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// SLICE-NEXT: %[[HIGH_WAKE:[0-9]+]] = arith.select %[[HIGH_CHANGED]], %[[HIGH_CHANGE_OBSERVER]], %[[NO_HIGH_WAKE]] : i64
// SLICE-NEXT: schedule.ready.update @__talos_aot_model_ingress_v1[0], %[[HIGH_WAKE]] {capacity = 64 : i64, consume = false}
// SLICE-NEXT: cf.br
// PLAN-LABEL: llvm.func @report(
// PLAN: llvm.call @talos_rt_v1_display(
// PLAN-LABEL: llvm.func @report.__talos_eval_private_
// PLAN: llvm.call @talos_rt_v1_scheduler_time(
// PLAN: llvm.call @talos_rt_v1_eval_display(
// PLAN: llvm.func @__talos_eval_dispatch_v1
!wide = !simulation.logic<65>
!wref = !simulation.ref<!wide>
!ref = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32} {
  simulation.design @wide_publication {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !wide design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "publish"
    simulation.code_unit.decl 4 in 0 always hierarchy "change"
    simulation.code_unit.decl 5 in 0 always hierarchy "posedge"
    simulation.code_unit.decl 6 in 0 initial hierarchy "check"
    simulation.code_unit.decl 7 in 0 function hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %data = simulation.context.storage %ctx[1] : !wref
      %change = simulation.context.storage %ctx[2] : !ref
      %edge = simulation.context.storage %ctx[3] : !ref
      %zero = arith.constant false
      %zeros = simulation.logic.constant 0 : i65, 0 : i65 : !wide
      simulation.ref.store %zero to %clk : i1, !ref
      simulation.ref.store %zeros to %data : !wide, !wref
      simulation.ref.store %zero to %change : i1, !ref
      simulation.ref.store %zero to %edge : i1, !ref
      %a = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %b = simulation.spawn @publish(%ctx, %clk, %data) : !simulation.context, !ref, !wref -> !simulation.process
      %c = simulation.spawn @change(%ctx, %data, %change) : !simulation.context, !wref, !ref -> !simulation.process
      %d = simulation.spawn @edge(%ctx, %data, %edge) : !simulation.context, !wref, !ref -> !simulation.process
      %e = simulation.spawn @check(%ctx, %data, %change, %edge) : !simulation.context, !wref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !ref -> i1
      %one = arith.constant true
      %new = arith.xori %old, %one : i1
      simulation.ref.store %new to %clk : i1, !ref
      cf.br ^wait
    }
    simulation.func @publish(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^write {site = #schedule.continuation<id = 2>} : !ref
    ^write:
      %value = simulation.ref.load %clk : !ref -> i1
      %reported = simulation.call @report(%ctx, %value) : (!simulation.context, i1) -> i1
      cf.cond_br %reported, ^high, ^low
    ^high:
      %h = simulation.logic.constant 18446744073709551616 : i65, 0 : i65 : !wide
      simulation.ref.store %h to %data : !wide, !wref
      cf.br ^wait
    ^low:
      %l = simulation.logic.constant 18446744073709551615 : i65, 0 : i65 : !wide
      simulation.ref.store %l to %data : !wide, !wref
      cf.br ^wait
    }
    simulation.func @change(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %flag: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %data to ^changed {site = #schedule.continuation<id = 3>} : !wref
    ^changed:
      %one = arith.constant true
      simulation.ref.store %one to %flag : i1, !ref
      cf.br ^wait
    }
    simulation.func @edge(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %flag: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %data edges [1] to ^edge {site = #schedule.continuation<id = 4>} : !wref
    ^edge:
      %one = arith.constant true
      simulation.ref.store %one to %flag : i1, !ref
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %change: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %edge: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %format = simulation.bytes.constant "%017h %b %b"
      %stdout = arith.constant 1 : i32
      %delay = simulation.time.constant 3
      simulation.suspend.delay %delay to ^first {site = #schedule.continuation<id = 5>, timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^first:
      %v0 = simulation.ref.load %data : !wref -> !wide
      %c0 = simulation.ref.load %change : !ref -> i1
      %e0 = simulation.ref.load %edge : !ref -> i1
      simulation.display %ctx to %stdout(%format, %v0, %c0, %e0) newline = true radix = <decimal> flags = [0, 0, 0, 0] : !simulation.bytes, !wide, i1, i1
      %two = simulation.time.constant 2
      simulation.suspend.delay %two to ^second {site = #schedule.continuation<id = 6>, timing = #schedule.timing_site<id = 2, kind = calendar>}
    ^second:
      %v1 = simulation.ref.load %data : !wref -> !wide
      %c1 = simulation.ref.load %change : !ref -> i1
      %e1 = simulation.ref.load %edge : !ref -> i1
      simulation.display %ctx to %stdout(%format, %v1, %c1, %e1) newline = true radix = <decimal> flags = [0, 0, 0, 0] : !simulation.bytes, !wide, i1, i1
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %value: i1 {simulation.capture_kind = 2 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %format = simulation.bytes.constant "copy %b at %0d"
      %stderr = arith.constant -2147483646 : i32
      %now = simulation.time.now %ctx
      simulation.display %ctx to %stderr(%format, %value, %now) newline = true radix = <decimal> flags = [0, 0, 0] {scope = "report"} : !simulation.bytes, i1, i64
      simulation.return %value : i1
    }
  }
}
