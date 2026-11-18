// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off},schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true}))' | FileCheck %s

// mem is an unpacked array of 3-bit elements laid out one byte each, so bits
// 3..7 of every byte are padding. @reader reads every element through a
// dynamic index; its live input lanes are each element's three logical bits,
// split only by padding. Padding belongs to no element and never changes, so
// watching it adds no event (IEEE 1800-2023 9.4.2): the fused kernel watches
// the whole array once instead of one view per element. @comb_z's watch of
// mem[0] lies inside that whole-array watch and is dropped as well.
// CHECK-LABEL: simulation.design @padded_array_watch
// CHECK: simulation.func private @__talos_region_kernel_{{[0-9_]+}}(
// CHECK-DAG: %[[MEM:.+]] = simulation.context.storage %arg0[0]
// CHECK-DAG: %[[IDX:.+]] = simulation.context.storage %arg0[1]
// CHECK: simulation.suspend.any %[[MEM]], %[[IDX]] edges [0, 0] to

!e = !simulation.packed_array<2 : 0 x !simulation.logic<1>>
!mem = !simulation.unpacked_array<0 : 7 x !e, #simulation.storage_layout<size = 8, alignment = 1, stride = 1, offsets = []>>
!i = !simulation.packed_array<2 : 0 x !simulation.logic<1>>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @padded_array_watch {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !mem design
    simulation.storage.decl 1 in 0 : !i design
    simulation.storage.decl 2 in 0 : !e design
    simulation.storage.decl 3 in 0 : !e design
    simulation.storage.decl 4 in 0 : !e design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "comb_y"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "comb_z"
    simulation.code_unit.decl 4 in 0 initial hierarchy "check"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %p0 = simulation.spawn @reader(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @comb_y(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @comb_z(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // always_comb rd = mem[idx];
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %mem = simulation.context.storage %ctx[0] : !simulation.ref<!mem>
      %idx = simulation.context.storage %ctx[1] : !simulation.ref<!i>
      %rd = simulation.context.storage %ctx[2] : !simulation.ref<!e>
      cf.br ^body
    ^body:
      %i = simulation.ref.load %idx : !simulation.ref<!i> -> !i
      %iflat = simulation.packed.flatten %i : (!i) -> !simulation.logic<3>
      %index = simulation.logic.resize %iflat signed = false : !simulation.logic<3> -> !simulation.logic<65>
      %element = simulation.ref.array_element %mem[%index] : (!simulation.ref<!mem>, !simulation.logic<65>) -> !simulation.ref<!e>
      %v = simulation.ref.load %element : !simulation.ref<!e> -> !e
      simulation.ref.store %v to %rd {simulation.continuous_store} : !e, !simulation.ref<!e>
      simulation.suspend.any %mem, %idx edges [0, 0] to ^body : !simulation.ref<!mem>, !simulation.ref<!i>
    }
    // always_comb rd2 = rd + 1;
    simulation.func @comb_y(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %rd = simulation.context.storage %ctx[2] : !simulation.ref<!e>
      %rd2 = simulation.context.storage %ctx[3] : !simulation.ref<!e>
      %one = simulation.logic.constant 1 : i3, 0 : i3 : !simulation.logic<3>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %rd : !simulation.ref<!e> -> !e
      %flat = simulation.packed.flatten %v : (!e) -> !simulation.logic<3>
      %sum = simulation.logic.binary add %flat, %one : !simulation.logic<3>
      %out = simulation.packed.unflatten %sum : (!simulation.logic<3>) -> !e
      simulation.ref.store %out to %rd2 {simulation.continuous_store} : !e, !simulation.ref<!e>
      simulation.suspend.change %rd to ^body : !simulation.ref<!e>
    }
    // always_comb rd3 = rd2 ^ mem[0];
    simulation.func @comb_z(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %mem = simulation.context.storage %ctx[0] : !simulation.ref<!mem>
      %rd2 = simulation.context.storage %ctx[3] : !simulation.ref<!e>
      %rd3 = simulation.context.storage %ctx[4] : !simulation.ref<!e>
      %first = simulation.ref.subelement %mem[[0]] : !simulation.ref<!mem> -> !simulation.ref<!e>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %rd2 : !simulation.ref<!e> -> !e
      %b = simulation.ref.load %first : !simulation.ref<!e> -> !e
      %af = simulation.packed.flatten %a : (!e) -> !simulation.logic<3>
      %bf = simulation.packed.flatten %b : (!e) -> !simulation.logic<3>
      %x = simulation.logic.binary xor %af, %bf : !simulation.logic<3>
      %out = simulation.packed.unflatten %x : (!simulation.logic<3>) -> !e
      simulation.ref.store %out to %rd3 {simulation.continuous_store} : !e, !simulation.ref<!e>
      simulation.suspend.any %rd2, %first edges [0, 0] to ^body : !simulation.ref<!e>, !simulation.ref<!e>
    }
    // Keeps rd3 live.
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %rd3 = simulation.context.storage %ctx[4] : !simulation.ref<!e>
      %one = simulation.time.constant 1
      %format = simulation.bytes.constant "rd3=%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %one to ^sample
    ^sample:
      %v = simulation.ref.load %rd3 : !simulation.ref<!e> -> !e
      %flat = simulation.packed.flatten %v : (!e) -> !simulation.logic<3>
      simulation.display %ctx to %stdout(%format, %flat) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, !simulation.logic<3>
      simulation.return
    }
  }
}

// -----

// @reader reads only mem[0] and mem[2]. Element 1 holds live logical bits
// that no member reads: a dead lane, not padding. The kernel must keep it out
// of the watch rather than merge mem[0] and mem[2] across it.
// CHECK-LABEL: simulation.design @dead_lane
// CHECK: simulation.func private @__talos_region_kernel_{{[0-9_]+}}(
// CHECK-DAG: %[[E0:.+]] = simulation.ref.subelement %{{.+}}{{\[\[0\]\]}}
// CHECK-DAG: %[[E2:.+]] = simulation.ref.subelement %{{.+}}{{\[\[2\]\]}}
// CHECK: simulation.suspend.any %[[E0]], %[[E2]] edges [0, 0] to

!e = !simulation.packed_array<2 : 0 x !simulation.logic<1>>
!mem = !simulation.unpacked_array<0 : 7 x !e, #simulation.storage_layout<size = 8, alignment = 1, stride = 1, offsets = []>>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @dead_lane {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !mem design
    simulation.storage.decl 1 in 0 : !e design
    simulation.storage.decl 2 in 0 : !e design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "comb_y"
    simulation.code_unit.decl 4 in 0 initial hierarchy "check"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %p0 = simulation.spawn @reader(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @comb_y(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %mem = simulation.context.storage %ctx[0] : !simulation.ref<!mem>
      %rd = simulation.context.storage %ctx[1] : !simulation.ref<!e>
      %e0 = simulation.ref.subelement %mem[[0]] : !simulation.ref<!mem> -> !simulation.ref<!e>
      %e2 = simulation.ref.subelement %mem[[2]] : !simulation.ref<!mem> -> !simulation.ref<!e>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %e0 : !simulation.ref<!e> -> !e
      %b = simulation.ref.load %e2 : !simulation.ref<!e> -> !e
      %af = simulation.packed.flatten %a : (!e) -> !simulation.logic<3>
      %bf = simulation.packed.flatten %b : (!e) -> !simulation.logic<3>
      %x = simulation.logic.binary xor %af, %bf : !simulation.logic<3>
      %out = simulation.packed.unflatten %x : (!simulation.logic<3>) -> !e
      simulation.ref.store %out to %rd {simulation.continuous_store} : !e, !simulation.ref<!e>
      simulation.suspend.change %mem to ^body : !simulation.ref<!mem>
    }
    simulation.func @comb_y(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %rd = simulation.context.storage %ctx[1] : !simulation.ref<!e>
      %rd2 = simulation.context.storage %ctx[2] : !simulation.ref<!e>
      %one = simulation.logic.constant 1 : i3, 0 : i3 : !simulation.logic<3>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %rd : !simulation.ref<!e> -> !e
      %flat = simulation.packed.flatten %v : (!e) -> !simulation.logic<3>
      %sum = simulation.logic.binary add %flat, %one : !simulation.logic<3>
      %out = simulation.packed.unflatten %sum : (!simulation.logic<3>) -> !e
      simulation.ref.store %out to %rd2 {simulation.continuous_store} : !e, !simulation.ref<!e>
      simulation.suspend.change %rd to ^body : !simulation.ref<!e>
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %rd3 = simulation.context.storage %ctx[2] : !simulation.ref<!e>
      %one = simulation.time.constant 1
      %format = simulation.bytes.constant "rd2=%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %one to ^sample
    ^sample:
      %v = simulation.ref.load %rd3 : !simulation.ref<!e> -> !e
      %flat = simulation.packed.flatten %v : (!e) -> !simulation.logic<3>
      simulation.display %ctx to %stdout(%format, %flat) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, !simulation.logic<3>
      simulation.return
    }
  }
}
