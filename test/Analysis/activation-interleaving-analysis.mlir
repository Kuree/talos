// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-activation-regions{functions=selector,store_control_inv interleaving=true order=true},test-talos-activation-regions{functions=selector_last,store_control interleaving=true order=true},test-talos-activation-regions{functions=producer,consumer interleaving=true order=true})' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -o %t.original
// RUN: diff %t.original %t.analyzed

// One design, one query per cohort (a pass instance per function subset).
// The analysis must not mutate the IR (diff above).
// The controller pulses only on valid=0, but the selector's final valid is
// 1: a cohort-written guard is not a free input (IEEE 1800-2023 4.6).
// CHECK: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable frontiers=1
// CHECK-NEXT: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable frontiers=1
// CHECK-NEXT: region order: cyclic
// A later unconditional store makes the final valid 0, so the controller
// cannot pulse: an earlier store is not the final value.
// CHECK: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable frontiers=1
// CHECK-NEXT: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable frontiers=1
// CHECK-NEXT: region order: cyclic
// Opposite polarities on a shared enable never pulse together.
// CHECK: interleaving order: acyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable frontiers=0
// CHECK-NEXT: interleaving order: acyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable frontiers=0
// CHECK-NEXT: region order: acyclic
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @negatives {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.storage.decl 5 in 0 : !b design
  simulation.storage.decl 6 in 0 : !b design
  simulation.storage.decl 7 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "selector"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "selector_last"
  simulation.code_unit.decl 3 in 0 always_comb hierarchy "store"
  simulation.code_unit.decl 4 in 0 always_comb hierarchy "store_inv"
  simulation.code_unit.decl 5 in 0 always_comb hierarchy "producer"
  simulation.code_unit.decl 6 in 0 always_comb hierarchy "consumer"
  simulation.func @selector(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
    %mode = simulation.context.storage %ctx[0] : !r
    %in = simulation.context.storage %ctx[1] : !r
    %valid = simulation.context.storage %ctx[2] : !r
    %grant = simulation.context.storage %ctx[3] : !r
    %req = simulation.context.storage %ctx[4] : !r
    %zero = simulation.logic.constant false, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %valid : !b, !r
    simulation.ref.store %zero to %req : !b, !r
    %m = simulation.ref.load %mode : !r -> !b
    %sel = simulation.logic.is_true %m : !b
    cf.cond_br %sel, ^sel, ^wait
  ^sel:
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %valid : !b, !r
    %g = simulation.ref.load %grant : !r -> !b
    simulation.ref.store %g to %req : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.any %mode, %in, %grant edges [0, 0, 0] to ^body : !r, !r, !r
  }
  simulation.func @selector_last(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
    %mode = simulation.context.storage %ctx[0] : !r
    %in = simulation.context.storage %ctx[1] : !r
    %valid = simulation.context.storage %ctx[2] : !r
    %grant = simulation.context.storage %ctx[3] : !r
    %req = simulation.context.storage %ctx[4] : !r
    %zero = simulation.logic.constant false, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %valid : !b, !r
    simulation.ref.store %zero to %req : !b, !r
    %m = simulation.ref.load %mode : !r -> !b
    %sel = simulation.logic.is_true %m : !b
    cf.cond_br %sel, ^sel, ^wait
  ^sel:
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %valid : !b, !r
    %g = simulation.ref.load %grant : !r -> !b
    simulation.ref.store %g to %req : !b, !r
    cf.br ^wait
  ^wait:
    simulation.ref.store %zero to %valid : !b, !r
    simulation.suspend.any %mode, %in, %grant edges [0, 0, 0] to ^body : !r, !r, !r
  }
  simulation.func @store_control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
    %valid = simulation.context.storage %ctx[2] : !r
    %grant = simulation.context.storage %ctx[3] : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %grant : !b, !r
    %v = simulation.ref.load %valid : !r -> !b
    %t = simulation.logic.is_true %v : !b
    cf.cond_br %t, ^req, ^wait
  ^req:
    simulation.ref.store %one to %grant : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.change %valid to ^body : !r
  }
  simulation.func @store_control_inv(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
    %valid = simulation.context.storage %ctx[2] : !r
    %grant = simulation.context.storage %ctx[3] : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %grant : !b, !r
    %v = simulation.ref.load %valid : !r -> !b
    %nv = simulation.logic.unary bit_not %v : (!b) -> !b
    %t = simulation.logic.is_true %nv : !b
    cf.cond_br %t, ^req, ^wait
  ^req:
    simulation.ref.store %one to %grant : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.change %valid to ^body : !r
  }
  simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
    %out = simulation.context.storage %ctx[6] : !r
    %in = simulation.context.storage %ctx[5] : !r
    %gate = simulation.context.storage %ctx[7] : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %out : !b, !r
    %e = simulation.ref.load %gate : !r -> !b
    %t = simulation.logic.is_true %e : !b
    cf.cond_br %t, ^set, ^wait
  ^set:
    simulation.ref.store %one to %out : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.any %gate, %in edges [0, 0] to ^body : !r, !r
  }
  simulation.func @consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
    %out = simulation.context.storage %ctx[5] : !r
    %in = simulation.context.storage %ctx[6] : !r
    %gate = simulation.context.storage %ctx[7] : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %out : !b, !r
    %e = simulation.ref.load %gate : !r -> !b
    %t = simulation.logic.is_true %e : !b
    cf.cond_br %t, ^wait, ^set
  ^set:
    simulation.ref.store %one to %out : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.any %gate, %in edges [0, 0] to ^body : !r, !r
  }
}
