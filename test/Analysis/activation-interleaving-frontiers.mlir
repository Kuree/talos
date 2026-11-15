// RUN: talos-opt %s --split-input-file '--test-talos-activation-regions=verify-prepared-views=true functions=selector,store_control,observer order=true interleaving=true' -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=SOURCE
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension{specialize-handle-tails=true}),talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=FUSED

// Reduced CVA6 LSU: the selector publishes valid, then consumes the
// controller's grant (and its earlier input load) in one arm; a passive
// observer joins. A saved continuation breaks the cycle (IEEE 1800-2023 4.6).
// CHECK-COUNT-2: interleaving order: acyclic refined=0 livelock-witness=1 preserved=n/a handoffs=3 frontiers=1
// CHECK: region order: cyclic
// The original actors hand off in the empty branch unless the body did.
// SOURCE-LABEL: simulation.design @raw
// SOURCE: simulation.func @selector(
// SOURCE: simulation.suspend.delay
// SOURCE-SAME: schedule.active_preemption_after = [@store_control]
// SOURCE: cf.br ^[[JOIN:bb[0-9]+]](
// SOURCE: ^[[JOIN]](%[[PASSED:[0-9]+]]: i1
// SOURCE-NEXT: cf.cond_br %[[PASSED]], ^[[REARM:bb[0-9]+]]({{.*}}), ^[[EMPTY:bb[0-9]+]](
// A virtual re-arm snapshots the watched inputs, and re-enters the body when
// a peer changed one while it waited (IEEE 1800-2023 4.7, 9.4.2).
// SOURCE: ^[[EMPTY]](
// SOURCE: simulation.suspend.delay {{.*}} to ^[[RECHECK:bb[0-9]+]](
// SOURCE: ^[[RECHECK]](
// SOURCE: simulation.logic.compare case_ne
// SOURCE: cf.cond_br %{{.*}}, ^[[BODY:bb[0-9]+]](%{{.*}}), ^[[REARM]](
// SOURCE: ^[[REARM]](
// SOURCE: simulation.suspend.any {{.*}} to ^[[BODY]]
// SOURCE-LABEL: simulation.func @store_control(
// SOURCE-NOT: simulation.suspend.delay
// SOURCE-LABEL: simulation.design @shared_case_tail
// The kernel reads the mode once and carries the input snapshot.
// FUSED-LABEL: simulation.design @raw
// FUSED: simulation.func private @__talos_region_kernel_
// FUSED: %[[MODE:.*]] = simulation.context.storage %arg0[0]
// FUSED: %[[INPUT:.*]] = simulation.context.storage %arg0[1]
// FUSED: %[[VALID:.*]] = simulation.context.storage %arg0[2]
// FUSED: %[[GRANT:.*]] = simulation.context.storage %arg0[3]
// FUSED: %[[EARLY:.*]] = simulation.ref.load %[[INPUT]]
// FUSED: simulation.ref.store %[[EARLY]] to %[[VALID]]
// FUSED: ^{{.*}}(%[[PATH:.*]]: i32, %[[SNAPSHOT:.*]]: !simulation.logic<1>):
// FUSED-NOT: simulation.ref.load %[[MODE]]
// FUSED-NOT: simulation.ref.load %[[INPUT]]
// FUSED: cf.switch %[[PATH]]
// FUSED: %[[LATE:.*]] = simulation.ref.load %[[GRANT]]
// FUSED: simulation.logic.binary and %[[LATE]], %[[SNAPSHOT]]
// FUSED: simulation.suspend.any %[[MODE]], %[[INPUT]] edges [0, 0]
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @raw {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.storage.decl 5 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "raw.selector"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "raw.store"
  simulation.code_unit.decl 4 in 0 always_comb hierarchy "raw.copy"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @selector(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @store_control(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process
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
    %both = simulation.logic.binary and %g, %v : !b
    simulation.ref.store %both to %req : !b, !r
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
  simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
    %valid = simulation.context.storage %ctx[2] : !r
    %copy = simulation.context.storage %ctx[5] : !r
    cf.br ^body
  ^body:
    %v = simulation.ref.load %valid : !r -> !b
    simulation.ref.store %v to %copy : !b, !r
    simulation.suspend.change %valid to ^body : !r
  }
}

// -----

// CFG tail sharing passes the chosen refs as arguments (9.2.2.2).
// CHECK-COUNT-2: interleaving order: acyclic refined=0 livelock-witness=1 preserved=n/a handoffs=2 frontiers=1
// CHECK: region order: cyclic
// FUSED-LABEL: simulation.design @shared_case_tail
// FUSED: simulation.func private @__talos_region_kernel_
// FUSED: cf.switch
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @shared_case_tail {
  simulation.scope.decl 0
  simulation.storage.decl 5 in 0 : !b design
  simulation.storage.decl 6 in 0 : !b design
  simulation.storage.decl 0 in 0 : !simulation.logic<2> design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "shared_case_tail.selector"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "shared_case_tail.store"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @selector(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @store_control(%ctx) : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func @selector(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
    %mode = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<2>>
    %ldValid = simulation.context.storage %ctx[5] : !r
    %ldReq = simulation.context.storage %ctx[6] : !r
    %in = simulation.context.storage %ctx[1] : !r
    %valid = simulation.context.storage %ctx[2] : !r
    %grant = simulation.context.storage %ctx[3] : !r
    %req = simulation.context.storage %ctx[4] : !r
    %zero = simulation.logic.constant false, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %valid : !b, !r
    simulation.ref.store %zero to %req : !b, !r
    simulation.ref.store %zero to %ldValid : !b, !r
    %load = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
    %store = simulation.logic.constant 2 : i2, 0 : i2 : !simulation.logic<2>
    %m = simulation.ref.load %mode : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
    %isLd = simulation.logic.compare case_eq %m, %load : (!simulation.logic<2>, !simulation.logic<2>) -> i1
    cf.cond_br %isLd, ^sel(%ldValid, %ldReq : !r, !r), ^test
  ^test:
    %isSt = simulation.logic.compare case_eq %m, %store : (!simulation.logic<2>, !simulation.logic<2>) -> i1
    cf.cond_br %isSt, ^sel(%valid, %grant : !r, !r), ^wait
  ^sel(%cv: !r, %cr: !r):
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %cv : !b, !r
    %g = simulation.ref.load %cr : !r -> !b
    simulation.ref.store %g to %req : !b, !r
    cf.br ^wait
  ^wait:
    simulation.suspend.any %mode, %in, %grant, %ldReq edges [0, 0, 0, 0] to ^body : !simulation.ref<!simulation.logic<2>>, !r, !r, !r
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
