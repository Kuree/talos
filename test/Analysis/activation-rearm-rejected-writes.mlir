// RUN: talos-opt %s -split-input-file '--test-talos-activation-regions=canonical-controls=true functions=first,second,third rearm-interleaving=true interleaving=true order=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -split-input-file -o %t.original
// RUN: diff %t.original %t.analyzed
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=false},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true})))' -o %t.before
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true})))' -o %t.after
// RUN: diff %t.before %t.after

// Pulse candidates whose stores or control effects make the witness invalid:
// no re-arm plan is built and materialization leaves the IR identical.

// IEEE 1800-2023 11.5.1: an invalid index makes a write a no-op. idx=0 never
// enters the branch, idx=1 is outside [0:0], X/Z skips it: neither process
// can pulse, and a one-element may-write envelope is not an exact write.
// CHECK: rearm plan: unchanged
// CHECK: livelock-witness=0 preserved=1
!bit = !simulation.logic<1>
!array = !simulation.packed_array<0 : 0 x !bit>
!ref = !simulation.ref<!bit>
!aref = !simulation.ref<!array>
module {
  simulation.design @out_of_bounds_pulses {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !array design
    simulation.storage.decl 1 in 0 : !array design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "t.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "t.second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %out = simulation.context.storage %ctx[0] : !aref
      %other = simulation.context.storage %ctx[1] : !aref
      %index = simulation.context.storage %ctx[2] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      %idx = simulation.ref.load %index : !ref -> !bit
      %take = simulation.logic.is_true %idx : !bit
      cf.cond_br %take, ^set, ^join
    ^set:
      %sel = simulation.ref.array_element %out[%idx] : (!aref, !bit) -> !ref
      simulation.ref.store %zero to %sel : !bit, !ref
      simulation.ref.store %one to %sel : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %other, %index edges [0, 0] to ^body : !aref, !ref
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %out = simulation.context.storage %ctx[1] : !aref
      %other = simulation.context.storage %ctx[0] : !aref
      %index = simulation.context.storage %ctx[2] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      %idx = simulation.ref.load %index : !ref -> !bit
      %take = simulation.logic.is_true %idx : !bit
      cf.cond_br %take, ^set, ^join
    ^set:
      %sel = simulation.ref.array_element %out[%idx] : (!aref, !bit) -> !ref
      simulation.ref.store %zero to %sel : !bit, !ref
      simulation.ref.store %one to %sel : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %other, %index edges [0, 0] to ^body : !aref, !ref
    }
  }
}

// -----

// IEEE 1800-2023 11.5.1: a dynamic destination's may-write range is not a
// definite final value. flags[0]=0; flags[idx]=1 does not imply flags[0]==1,
// so third's guard on flags[0] is no witness. The order stays cyclic.
// CHECK: rearm plan: unchanged
// CHECK: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1
!bit = !simulation.logic<1>
!flags = !simulation.packed_array<1 : 0 x !bit>
!ref = !simulation.ref<!bit>
!fref = !simulation.ref<!flags>
module {
  simulation.design @inexact_final_value {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !flags design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "t.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "t.second"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "t.third"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %flags = simulation.context.storage %ctx[0] : !fref
      %index = simulation.context.storage %ctx[3] : !ref
      %low = simulation.ref.extract %flags from 0 : !fref -> !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      simulation.ref.store %zero to %low : !bit, !ref
      simulation.ref.store %one to %index : !bit, !ref
      %p = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @third(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %flags = simulation.context.storage %ctx[0] : !fref
      %a = simulation.context.storage %ctx[1] : !ref
      %index = simulation.context.storage %ctx[3] : !ref
      %saved = simulation.context.storage %ctx[4] : !ref
      %low = simulation.ref.extract %flags from 0 : !fref -> !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      %old = simulation.ref.load %a : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      simulation.ref.store %zero to %low : !bit, !ref
      %idx = simulation.ref.load %index : !ref -> !bit
      %sel = simulation.ref.array_element %flags[%idx] : (!fref, !bit) -> !ref
      simulation.ref.store %one to %sel : !bit, !ref
      simulation.suspend.any %a, %index edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %flags = simulation.context.storage %ctx[0] : !fref
      %a = simulation.context.storage %ctx[1] : !ref
      %b = simulation.context.storage %ctx[2] : !ref
      %index = simulation.context.storage %ctx[3] : !ref
      %low = simulation.ref.extract %flags from 0 : !fref -> !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %a : !bit, !ref
      %flag = simulation.ref.load %low : !ref -> !bit
      %idx = simulation.ref.load %index : !ref -> !bit
      %flag_true = simulation.logic.is_true %flag : !bit
      %index_true = simulation.logic.is_true %idx : !bit
      %take = arith.andi %flag_true, %index_true : i1
      cf.cond_br %take, ^set, ^join
    ^set:
      simulation.ref.store %one to %a : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %low, %b, %index edges [0, 0, 0] to ^body : !ref, !ref, !ref
    }
    simulation.func @third(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[1] : !ref
      %b = simulation.context.storage %ctx[2] : !ref
      %saved = simulation.context.storage %ctx[5] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      %old = simulation.ref.load %a : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      simulation.ref.store %zero to %b : !bit, !ref
      simulation.ref.store %one to %b : !bit, !ref
      simulation.suspend.change %a to ^body : !ref
    }
  }
}

// -----

// An external hierarchical disable can observe the named activation, so the
// control effect is unsupported: the body is rejected and nothing changes.
// CHECK: regions @first valid=0 reason=memory effects
// CHECK: rearm interleaving: components=0
!ref = !simulation.ref<i1>
module {
  simulation.design @observable_controls {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "first"
    simulation.code_unit.decl 3 in 0 initial hierarchy "disabler"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @disabler(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %out = simulation.context.storage %ctx[0] : !ref
      %in = simulation.context.storage %ctx[1] : !ref
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      %scope = simulation.control.enter 10
      simulation.ref.store %zero to %out : i1, !ref
      simulation.ref.store %one to %out : i1, !ref
      simulation.control.leave %scope
      simulation.suspend.change %in to ^body : !ref
    }
    simulation.func @disabler(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      simulation.control.disable 10 {hierarchical = true}
      simulation.return
    }
  }
}
