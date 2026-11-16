// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-nba-influence)' -o /dev/null 2>&1 | FileCheck %s

// IEEE 1800-2023 9.3.2, 13.5, 13.5.2: copy-in, ref actuals and private
// copy-out carry influence across calls and forks, so storage 0 stays in
// guard storage 1's observer cone (9.4.2.3). Task-call scheduling keeps callee
// effects out of the caller summary; formals are resolved at every call level.
// CHECK-LABEL: influence formal_value_bridge
// CHECK-NEXT: storage 0 observed=1 unread=0
// CHECK-NEXT: storage 1 observed=1
// CHECK-NEXT: storage 2 observed=0 unread=1
// CHECK-LABEL: influence formal_spawn_value_bridge
// CHECK-NEXT: storage 0 observed=1 unread=0
// CHECK-NEXT: storage 1 observed=1
// CHECK-NEXT: storage 2 observed=0 unread=1
// CHECK-LABEL: influence formal_local_bridge
// CHECK-NEXT: storage 0 observed=1 unread=0
// CHECK-NEXT: storage 1 observed=1
// CHECK-NEXT: storage 2 observed=0 unread=1
// CHECK-LABEL: influence formal_tasks
// CHECK-NEXT: storage 0 observed=1 unread=0
// CHECK-NEXT: storage 1 observed=1 unread=1
// CHECK-NEXT: storage 2 observed=0 unread=1

// Copy-in keeps the source dependency although a scalar input formal has no
// design-storage Read effect in the callee.
!ref = !simulation.ref<i1>
module {
  simulation.design @formal_value_bridge {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design {test.observer}
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 2 in 0 task hierarchy "writer"
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %source = simulation.context.storage %ctx[0] : !ref
      %value = simulation.ref.load %source : !ref -> i1
      simulation.task.call @writer(%ctx, %value) arguments 2 to ^done : !simulation.context, i1
    ^done:
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %value: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 2 : i64} {
      %guard = simulation.context.storage %ctx[1] : !ref
      simulation.ref.store %value to %guard : i1, !ref
      simulation.return
    }
  }
}

// -----
// Same through a forked process.
!ref = !simulation.ref<i1>
module {
  simulation.design @formal_spawn_value_bridge {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design {test.observer}
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 2 in 0 fork hierarchy "writer"
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %source = simulation.context.storage %ctx[0] : !ref
      %value = simulation.ref.load %source : !ref -> i1
      %child = simulation.spawn @writer(%ctx, %value) : !simulation.context, i1 -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %value: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 2 : i64} {
      %guard = simulation.context.storage %ctx[1] : !ref
      simulation.ref.store %value to %guard : i1, !ref
      simulation.return
    }
  }
}

// -----
// A task moves a design read through a private actual into the caller's
// later observed write.
!ref = !simulation.ref<i1>
module {
  simulation.design @formal_local_bridge {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design {test.observer}
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 2 in 0 task hierarchy "reader"
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %guard = simulation.context.storage %ctx[1] : !ref
      %zero = arith.constant false
      %private = simulation.ref.alloc %zero : i1 -> !ref
      simulation.task.call @reader(%ctx, %private) arguments 2 to ^done : !simulation.context, !ref
    ^done:
      %value = simulation.ref.load %private : !ref -> i1
      simulation.ref.store %value to %guard : i1, !ref
      simulation.return
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %dst: !ref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 2 : i64} {
      %source = simulation.context.storage %ctx[0] : !ref
      %value = simulation.ref.load %source : !ref -> i1
      simulation.ref.store %value to %dst : i1, !ref
      simulation.return
    }
  }
}

// -----
// Ref formals alias their actuals through two task levels.
!ref = !simulation.ref<i1>
module {
  simulation.design @formal_tasks {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design {test.observer}
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 2 in 0 task hierarchy "outer"
    simulation.code_unit.decl 3 in 0 task hierarchy "inner"
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %source = simulation.context.storage %ctx[0] : !ref
      %guard = simulation.context.storage %ctx[1] : !ref
      simulation.task.call @outer(%ctx, %source, %guard) arguments 3 to ^done : !simulation.context, !ref, !ref
    ^done:
      simulation.return
    }
    simulation.func private @outer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %source: !ref {simulation.capture_kind = 1 : i32}, %guard: !ref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 2 : i64} {
      simulation.task.call @inner(%ctx, %source, %guard) arguments 3 to ^done : !simulation.context, !ref, !ref
    ^done:
      simulation.return
    }
    simulation.func private @inner(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %source: !ref {simulation.capture_kind = 1 : i32}, %guard: !ref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 3 : i64} {
      %value = simulation.ref.load %source : !ref -> i1
      simulation.ref.store %value to %guard : i1, !ref
      simulation.return
    }
  }
}
