// RUN: talos-opt %s -split-input-file '--test-talos-activation-regions=functions=first,second,third rearm-interleaving=true interleaving=true order=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -split-input-file -o %t.original
// RUN: diff %t.original %t.analyzed
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=false},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true})))' -o %t.before
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true})))' -o %t.after
// RUN: diff %t.before %t.after

// Two processes whose pulses are physically cyclic but whose guards (the
// pulse-cycle witness) cannot hold together: no re-arm plan is built, the
// analysis is read-only and materialization leaves the IR identical.

// Contradictory polarities of one gate.
// CHECK: rearm interleaving: components=1
// CHECK-NEXT: rearm plan: unchanged
// CHECK: livelock-witness=0 preserved=1
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module {
  simulation.design @contradictory_gate {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "t.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "t.second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %out = simulation.context.storage %ctx[1] : !ref
      %in = simulation.context.storage %ctx[0] : !ref
      %gate = simulation.context.storage %ctx[2] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %out : !bit, !ref
      %enabled = simulation.ref.load %gate : !ref -> !bit
      %test = simulation.logic.is_true %enabled : !bit
      cf.cond_br %test, ^set, ^join
    ^set:
      simulation.ref.store %one to %out : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %gate, %in edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %out = simulation.context.storage %ctx[0] : !ref
      %in = simulation.context.storage %ctx[1] : !ref
      %gate = simulation.context.storage %ctx[2] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %out : !bit, !ref
      %enabled = simulation.ref.load %gate : !ref -> !bit
      %test = simulation.logic.is_true %enabled : !bit
      cf.cond_br %test, ^join, ^set
    ^set:
      simulation.ref.store %one to %out : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %gate, %in edges [0, 0] to ^body : !ref, !ref
    }
  }
}

// -----

// 4-state: first needs index == 3, second needs flags[zext(index)] of a
// two-element array (index 0 or 1). An unknown or out-of-range read is never
// certified by picking an arbitrary bit of the array's may-read range.
// CHECK: rearm plan: unchanged
// CHECK: livelock-witness=0 preserved=1
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
!flags = !simulation.packed_array<1 : 0 x !bit>
!fref = !simulation.ref<!flags>
!idx = !simulation.logic<2>
module {
  simulation.design @index_guards {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !flags design
    simulation.storage.decl 3 in 0 : !idx design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "t.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "t.second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %index = simulation.context.storage %ctx[3] : !simulation.ref<!idx>
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %y : !bit, !ref
      %i = simulation.ref.load %index : !simulation.ref<!idx> -> !idx
      %three = simulation.logic.constant 3 : i2, 0 : i2 : !idx
      %hit = simulation.logic.compare case_eq %i, %three : (!idx, !idx) -> i1
      cf.cond_br %hit, ^set, ^join
    ^set:
      simulation.ref.store %one to %y : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %x, %index edges [0, 0] to ^body : !ref, !simulation.ref<!idx>
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %flags = simulation.context.storage %ctx[2] : !fref
      %index = simulation.context.storage %ctx[3] : !simulation.ref<!idx>
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %x : !bit, !ref
      %i = simulation.ref.load %index : !simulation.ref<!idx> -> !idx
      %wide = simulation.logic.resize %i signed = false : !idx -> !simulation.logic<65>
      %sel = simulation.ref.array_element %flags[%wide] : (!fref, !simulation.logic<65>) -> !ref
      %flag = simulation.ref.load %sel : !ref -> !bit
      %test = simulation.logic.is_true %flag : !bit
      cf.cond_br %test, ^set, ^join
    ^set:
      simulation.ref.store %one to %x : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %y, %flags, %index edges [0, 0, 0] to ^body : !ref, !fref, !simulation.ref<!idx>
    }
  }
}

// -----

// 2-state: first needs i2 index == -1; sign extension to 65 bits keeps it
// outside the two-element array, so second's selected-bit guard (flag true)
// can never hold with it.
// CHECK: rearm plan: unchanged
// CHECK: livelock-witness=0 preserved=1
!bit = i1
!ref = !simulation.ref<!bit>
!flags = !simulation.packed_array<1 : 0 x !bit>
!fref = !simulation.ref<!flags>
module {
  simulation.design @signed_out_of_bounds {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !flags design
    simulation.storage.decl 3 in 0 : i2 design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "t.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "t.second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %index = simulation.context.storage %ctx[3] : !simulation.ref<i2>
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %y : !bit, !ref
      %i = simulation.ref.load %index : !simulation.ref<i2> -> i2
      %m1 = arith.constant -1 : i2
      %hit = arith.cmpi eq, %i, %m1 : i2
      cf.cond_br %hit, ^set, ^join
    ^set:
      simulation.ref.store %one to %y : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %x, %index edges [0, 0] to ^body : !ref, !simulation.ref<i2>
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %flags = simulation.context.storage %ctx[2] : !fref
      %index = simulation.context.storage %ctx[3] : !simulation.ref<i2>
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %x : !bit, !ref
      %i = simulation.ref.load %index : !simulation.ref<i2> -> i2
      %wide = arith.extsi %i : i2 to i65
      %sel = simulation.ref.array_element %flags[%wide] : (!fref, i65) -> !ref
      %flag = simulation.ref.load %sel : !ref -> !bit
      cf.cond_br %flag, ^set, ^join
    ^set:
      simulation.ref.store %one to %x : !bit, !ref
      cf.br ^join
    ^join:
      simulation.suspend.any %y, %flags, %index edges [0, 0, 0] to ^body : !ref, !fref, !simulation.ref<i2>
    }
  }
}
