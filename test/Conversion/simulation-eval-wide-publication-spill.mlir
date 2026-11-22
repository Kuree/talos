// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' --mlir-print-ir-after=materialize-native-processes -o /dev/null 2>&1 | FileCheck %s

// A store of a value wider than a machine word to a captured reference
// publishes one transition per 64-bit slice of the root (IEEE 1800-2023
// 9.4.2). A plane up to 4096 bits wide gives each slice as a shift of the
// plane value. A wider plane is stored once to an entry-block temporary, live
// only around the slices, and each slice loads its bytes from it: LLVM
// legalizes integers that wide slowly. The last slice of a 4097-bit plane,
// one bit, loads its byte and truncates it, since a load of an integer that
// is not a whole number of bytes from memory that no store of that type
// wrote is undefined (LLVM LangRef, load).

// 4097 bits: each plane through a temporary.
// CHECK-LABEL: func.func private @spill.__talos_eval_body_0(
// CHECK-NEXT: llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[NEW_UNKNOWN_SLOT:[0-9]+]] = llvm.alloca %{{[0-9]+}} x i4097 {alignment = 1 : i64} : (i64) -> !llvm.ptr
// CHECK-NEXT: llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[NEW_SLOT:[0-9]+]] = llvm.alloca %{{[0-9]+}} x i4097 {alignment = 1 : i64} : (i64) -> !llvm.ptr
// CHECK-NEXT: llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[OLD_UNKNOWN_SLOT:[0-9]+]] = llvm.alloca %{{[0-9]+}} x i4097 {alignment = 1 : i64} : (i64) -> !llvm.ptr
// CHECK-NEXT: llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[OLD_SLOT:[0-9]+]] = llvm.alloca %{{[0-9]+}} x i4097 {alignment = 1 : i64} : (i64) -> !llvm.ptr
// CHECK: %[[OLD_WORDS:[0-9]+]] = schedule.state.load @__talos_state_value[1] {alignment = 1 : i64} : i4104
// CHECK-NEXT: %[[OLD:[0-9]+]] = llvm.trunc %[[OLD_WORDS]] : i4104 to i4097
// CHECK-NEXT: %[[OLD_UNKNOWN_WORDS:[0-9]+]] = schedule.state.load @__talos_state_unknown[1] {alignment = 1 : i64} : i4104
// CHECK-NEXT: %[[OLD_UNKNOWN:[0-9]+]] = llvm.trunc %[[OLD_UNKNOWN_WORDS]] : i4104 to i4097
// CHECK: %[[NEW:[0-9]+]] = arith.select %{{[0-9]+}}, %{{[^ ]+}}, %[[OLD]] : i4097
// CHECK: %[[NEW_UNKNOWN:[0-9]+]] = arith.select %{{[0-9]+}}, %{{[^ ]+}}, %[[OLD_UNKNOWN]] : i4097
// CHECK-NEXT: llvm.mlir.addressof @__talos_current_context
// CHECK-NEXT: llvm.load
// CHECK-NEXT: llvm.intr.lifetime.start %[[OLD_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.store %[[OLD]], %[[OLD_SLOT]] {alignment = 1 : i64} : i4097, !llvm.ptr
// CHECK-NEXT: llvm.intr.lifetime.start %[[OLD_UNKNOWN_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.store %[[OLD_UNKNOWN]], %[[OLD_UNKNOWN_SLOT]] {alignment = 1 : i64} : i4097, !llvm.ptr
// CHECK-NEXT: llvm.intr.lifetime.start %[[NEW_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.store %[[NEW]], %[[NEW_SLOT]] {alignment = 1 : i64} : i4097, !llvm.ptr
// CHECK-NEXT: llvm.intr.lifetime.start %[[NEW_UNKNOWN_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.store %[[NEW_UNKNOWN]], %[[NEW_UNKNOWN_SLOT]] {alignment = 1 : i64} : i4097, !llvm.ptr
// CHECK-NEXT: llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_SLOT]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK: llvm.mlir.constant(64 : i64) : i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_SLOT]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK: llvm.mlir.constant(4096 : i64) : i64
// CHECK-NEXT: %[[OLD_TOP:[0-9]+]] = llvm.getelementptr %[[OLD_SLOT]][512] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: %[[OLD_BIT_BYTE:[0-9]+]] = llvm.load %[[OLD_TOP]] {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: %[[OLD_BIT:[0-9]+]] = llvm.trunc %[[OLD_BIT_BYTE]] : i8 to i1
// CHECK-NEXT: llvm.zext %[[OLD_BIT]] : i1 to i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_UNKNOWN_SLOT]][512] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i1
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i1 to i64
// CHECK-NEXT: llvm.getelementptr %[[NEW_SLOT]][512] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i1
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i1 to i64
// CHECK-NEXT: llvm.getelementptr %[[NEW_UNKNOWN_SLOT]][512] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i1
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i1 to i64
// CHECK-NOT: !llvm.ptr -> i1{{$}}
// CHECK: schedule.ready.update @__talos_aot_model_ingress_v1
// CHECK-NEXT: llvm.intr.lifetime.end %[[OLD_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.intr.lifetime.end %[[OLD_UNKNOWN_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.intr.lifetime.end %[[NEW_SLOT]] : !llvm.ptr
// CHECK-NEXT: llvm.intr.lifetime.end %[[NEW_UNKNOWN_SLOT]] : !llvm.ptr
// CHECK-NEXT: cf.br

!wide = !simulation.logic<4097>
!wref = !simulation.ref<!wide>
!ref = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32} {
  simulation.design @spill {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !wide design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "spill"
    simulation.code_unit.decl 4 in 0 always hierarchy "change"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %data = simulation.context.storage %ctx[1] : !wref
      %zero = arith.constant false
      %zeros = simulation.logic.constant 0 : i4097, 0 : i4097 : !wide
      simulation.ref.store %zero to %clk : i1, !ref
      simulation.ref.store %zeros to %data : !wide, !wref
      %a = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %b = simulation.spawn @spill(%ctx, %clk, %data) : !simulation.context, !ref, !wref -> !simulation.process
      %c = simulation.spawn @change(%ctx, %data) : !simulation.context, !wref -> !simulation.process
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
    simulation.func @spill(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^write {site = #schedule.continuation<id = 2>} : !ref
    ^write:
      %value = simulation.logic.constant 1 : i4097, 0 : i4097 : !wide
      simulation.ref.store %value to %data : !wide, !wref
      cf.br ^wait
    }
    simulation.func @change(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %data to ^wait {site = #schedule.continuation<id = 3>} : !wref
    }
  }
}

// -----

// 4096 bits, the widest plane without a temporary: shifts.
// CHECK-LABEL: func.func private @shift.__talos_eval_body_0(
// CHECK-NOT: llvm.alloca
// CHECK: %[[OLD:[0-9]+]] = schedule.state.load @__talos_state_value[1] {alignment = 1 : i64} : i4096
// CHECK-NEXT: %[[OLD_UNKNOWN:[0-9]+]] = schedule.state.load @__talos_state_unknown[1] {alignment = 1 : i64} : i4096
// CHECK: %[[NEW:[0-9]+]] = arith.select %{{[0-9]+}}, %{{[^ ]+}}, %[[OLD]] : i4096
// CHECK: %[[NEW_UNKNOWN:[0-9]+]] = arith.select %{{[0-9]+}}, %{{[^ ]+}}, %[[OLD_UNKNOWN]] : i4096
// CHECK-NOT: llvm.alloca
// CHECK: llvm.trunc %[[OLD]] : i4096 to i64
// CHECK-NEXT: llvm.trunc %[[OLD_UNKNOWN]] : i4096 to i64
// CHECK-NEXT: llvm.trunc %[[NEW]] : i4096 to i64
// CHECK-NEXT: llvm.trunc %[[NEW_UNKNOWN]] : i4096 to i64
// CHECK: llvm.mlir.constant(4032 : i64) : i64
// CHECK-NEXT: %[[TOP:[0-9]+]] = llvm.mlir.constant(4032 : i4096) : i4096
// CHECK-NEXT: %[[OLD_TOP:[0-9]+]] = llvm.lshr %[[OLD]], %[[TOP]] : i4096
// CHECK-NEXT: llvm.trunc %[[OLD_TOP]] : i4096 to i64
// CHECK-NOT: llvm.alloca
// CHECK-NOT: llvm.intr.lifetime
// CHECK: return

!wide = !simulation.logic<4096>
!wref = !simulation.ref<!wide>
!ref = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32} {
  simulation.design @shift {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !wide design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "shift"
    simulation.code_unit.decl 4 in 0 always hierarchy "change"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %data = simulation.context.storage %ctx[1] : !wref
      %zero = arith.constant false
      %zeros = simulation.logic.constant 0 : i4096, 0 : i4096 : !wide
      simulation.ref.store %zero to %clk : i1, !ref
      simulation.ref.store %zeros to %data : !wide, !wref
      %a = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %b = simulation.spawn @shift(%ctx, %clk, %data) : !simulation.context, !ref, !wref -> !simulation.process
      %c = simulation.spawn @change(%ctx, %data) : !simulation.context, !wref -> !simulation.process
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
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^write {site = #schedule.continuation<id = 2>} : !ref
    ^write:
      %value = simulation.logic.constant 1 : i4096, 0 : i4096 : !wide
      simulation.ref.store %value to %data : !wide, !wref
      cf.br ^wait
    }
    simulation.func @change(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %data to ^wait {site = #schedule.continuation<id = 3>} : !wref
    }
  }
}
