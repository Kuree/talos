// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,test-talos-activation-regions{verify-prepared-views=true functions=first,peer0,peer1 interleaving=true order=true dump=true})' -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,test-talos-activation-regions{verify-prepared-views=true functions=first,peer0,peer1 rearm-interleaving=true})' -o /dev/null 2>&1 | FileCheck %s --check-prefix=REARM
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=PREEMPT
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph),test-talos-simulation-schedule-analysis{preemptions=true})' -o /dev/null 2>&1 | FileCheck %s --check-prefix=RANK
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=PREEMPT

// Each actor pulses an input of the next, then consumes its result: four runs
// and three handoffs is a lower bound. Choosing the first ready actor by
// identity needs four; the exact search runs first, peer0, peer1, first
// (IEEE 1800-2023 4.6, 9.2.2.2).
// CHECK: interleaving order: acyclic refined=0 livelock-witness=1 preserved=n/a handoffs=3
// CHECK-NEXT: interleaving runs: @first @peer0 @peer1 @first
// CHECK-NEXT: interleaving order: acyclic refined=0 livelock-witness=1 preserved=n/a handoffs=3
// CHECK-NEXT: interleaving runs: @first @peer0 @peer1 @first
// CHECK: region order: acyclic
// Holding the first process before re-arm also takes three handoffs.
// REARM: rearm interleaving: components=1
// REARM-NEXT: rearm plan: handoffs=3 preemptions= @first
// Direct and transitive upstream producers must run before the held first
// actor snapshots its input; feedback peers use the handoff instead.
// upstream1 reads the feedback only for an unrelated output (CVA6 FIFO), so
// owner-level reachability must not invent a cycle.
// RANK: preemption @first ordered=1
// RANK-NEXT: preemption input @first after @upstream0 ordered=1
// RANK-NEXT: preemption input @first after @upstream1 ordered=1
// RANK-NOT: preemption input
// The earlier external snapshot crosses the handoff as an SSA value.
// PREEMPT-LABEL: simulation.func @first(
// PREEMPT-NOT: schedule.eval.body
// PREEMPT: %[[SNAPSHOT:[0-9]+]] = simulation.ref.load
// PREEMPT: simulation.ref.store
// PREEMPT: simulation.ref.store
// PREEMPT-NOT: simulation.ref.load
// PREEMPT: %[[ZERO:[0-9]+]] = simulation.time.constant 0
// PREEMPT-NEXT: simulation.suspend.delay %[[ZERO]] to ^[[READ:bb[0-9]+]](
// PREEMPT-SAME: %[[SNAPSHOT]]
// PREEMPT-SAME: resume_region = 2 : i32
// PREEMPT-SAME: schedule.active_preemption_after = [@peer0, @peer1]
// PREEMPT: ^[[READ]](
// PREEMPT: simulation.ref.load
// PREEMPT: simulation.logic.binary xor
// PREEMPT: simulation.suspend.any

!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @three_actor_ring {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.storage.decl 5 in 0 : !b design
  simulation.storage.decl 6 in 0 : !b design
  simulation.storage.decl 7 in 0 : !b design
  simulation.storage.decl 8 in 0 : !b design
  simulation.storage.decl 9 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "first"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "peer#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
  simulation.code_unit.decl 4 in 0 continuous hierarchy "upstream0"
  simulation.code_unit.decl 5 in 0 always_comb hierarchy "upstream1"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @"peer#"(%ctx) {test.replicate = 2 : i64} : !simulation.context -> !simulation.process
    simulation.spawn @upstream0(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @upstream1(%ctx) : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
    %out = simulation.context.storage %ctx[0] : !r
    %in = simulation.context.storage %ctx[1] : !r
    %saved = simulation.context.storage %ctx[3] : !r
    %external = simulation.context.storage %ctx[6] : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    %snapshot = simulation.ref.load %external : !r -> !b
    simulation.ref.store %zero to %out : !b, !r
    simulation.ref.store %one to %out : !b, !r
    %v = simulation.ref.load %in : !r -> !b
    %x = simulation.logic.binary xor %v, %snapshot : !b
    simulation.ref.store %x to %saved : !b, !r
    simulation.suspend.any %in, %external edges [0, 0] to ^body : !r, !r
  }
  simulation.func @"peer#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
    %out = simulation.context.storage %ctx[2] {test.replicate_stride = {id = -1 : i64}} : !r
    %in = simulation.context.storage %ctx[0] {test.replicate_stride = {id = 2 : i64}} : !r
    %saved = simulation.context.storage %ctx[5] {test.replicate_stride = {id = -1 : i64}} : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    simulation.ref.store %zero to %out : !b, !r
    simulation.ref.store %one to %out : !b, !r
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %saved : !b, !r
    simulation.suspend.change %in to ^body : !r
  }
  simulation.func @upstream0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    %in = simulation.context.storage %ctx[7] : !r
    %out = simulation.context.storage %ctx[8] : !r
    cf.br ^body
  ^body:
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %out : !b, !r
    simulation.suspend.change %in to ^body : !r
  }
  simulation.func @upstream1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
    %in = simulation.context.storage %ctx[8] : !r
    %out = simulation.context.storage %ctx[6] : !r
    %feedback = simulation.context.storage %ctx[0] : !r
    %unrelated = simulation.context.storage %ctx[9] : !r
    cf.br ^body
  ^body:
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %out : !b, !r
    %o = simulation.ref.load %feedback : !r -> !b
    simulation.ref.store %o to %unrelated : !b, !r
    simulation.suspend.any %in, %feedback edges [0, 0] to ^body : !r, !r
  }
}
