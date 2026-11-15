// RUN: talos-opt %s --split-input-file '--test-talos-activation-regions=verify-prepared-views=true functions=selector,store_control,observer order=true interleaving=true' -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension{specialize-handle-tails=true}),talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=FUSED

// A short-circuit prefix phi and an unrelated first publication (dummy):
// successive frontiers are needed, the first store leaves the cycle intact.
// CHECK-COUNT-2: interleaving order: acyclic refined=0 livelock-witness=1 preserved=n/a handoffs=2 frontiers=1
// CHECK: region order: cyclic
// FUSED-LABEL: simulation.design @multiple_publications
// FUSED: simulation.func private @__talos_region_kernel_
// FUSED: %[[VALID:.*]] = simulation.context.storage %arg0[2]
// FUSED: %[[GRANT:.*]] = simulation.context.storage %arg0[3]
// FUSED: %[[DUMMY:.*]] = simulation.context.storage %arg0[5]
// FUSED: simulation.ref.store {{.*}} to %[[DUMMY]]
// FUSED: simulation.ref.store {{.*}} to %[[DUMMY]]
// FUSED: simulation.ref.store {{.*}} to %[[VALID]]
// FUSED: simulation.ref.store {{.*}} to %[[GRANT]]
// FUSED: cf.switch
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @multiple_publications {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.storage.decl 5 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "multiple_publications.selector"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "multiple_publications.store"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @selector(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @store_control(%ctx) : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func @selector(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
    %mode = simulation.context.storage %ctx[0] : !r
    %in = simulation.context.storage %ctx[1] : !r
    %valid = simulation.context.storage %ctx[2] : !r
    %grant = simulation.context.storage %ctx[3] : !r
    %req = simulation.context.storage %ctx[4] : !r
    %dummy = simulation.context.storage %ctx[5] : !r
    %one = simulation.logic.constant true, false : !b
    %no = arith.constant false
    %zero = simulation.logic.constant false, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %valid : !b, !r
    simulation.ref.store %zero to %req : !b, !r
    simulation.ref.store %zero to %dummy : !b, !r
    %m = simulation.ref.load %mode : !r -> !b
    %sel = simulation.logic.is_true %m : !b
    cf.cond_br %sel, ^enable, ^guard(%no : i1)
  ^enable:
    %x = simulation.ref.load %in : !r -> !b
    %en = simulation.logic.is_true %x : !b
    cf.br ^guard(%en : i1)
  ^guard(%ok: i1):
    cf.cond_br %ok, ^sel, ^wait
  ^sel:
    simulation.ref.store %one to %dummy : !b, !r
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %valid : !b, !r
    %g = simulation.ref.load %grant : !r -> !b
    simulation.ref.store %g to %req : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.any %mode, %in, %grant edges [0, 0, 0] to ^body : !r, !r, !r
  }
  simulation.func @store_control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
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
}

// -----

// An edge observer outside the cohort sees the valid pulses: the original
// processes and subscriptions stay (4.6).
// CHECK-COUNT-2: interleaving order: acyclic refined=0 livelock-witness=1 preserved=n/a handoffs=2 frontiers=1
// CHECK: region order: cyclic
// FUSED-LABEL: simulation.design @outside_edge_observer
// FUSED: simulation.spawn @selector
// FUSED: simulation.spawn @store_control
// FUSED: simulation.spawn @edge_sample
// FUSED-NOT: __talos_region_kernel_
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @outside_edge_observer {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.storage.decl 5 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "outside_edge_observer.selector"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "outside_edge_observer.store"
  simulation.code_unit.decl 4 in 0 always hierarchy "outside_edge_observer.watch"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @selector(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @store_control(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @edge_sample(%ctx) : !simulation.context -> !simulation.process
    simulation.return
  }
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
  simulation.func @store_control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
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
  simulation.func @edge_sample(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
    %valid = simulation.context.storage %ctx[2] : !r
    %copy = simulation.context.storage %ctx[5] : !r
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %valid to ^body : !r
  ^body:
    %v = simulation.ref.load %valid : !r -> !b
    simulation.nba.enqueue %v to %copy : (!b, !r) -> ()
    cf.br ^wait
  }
}
