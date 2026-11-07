// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// IEEE 1800-2023 4.3/4.6/9.4.2/10.4.1: implicit holds use the same
// closed observation proof as explicit self-assignment. Idempotence never
// authorizes dropping an old snapshot, counting transitions, exposing a pulse,
// sharing a held cell with another writer, or choosing an unresolved alias.
// Growth is off so @held exercises the transitive observer proof from outside.
!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @implicit_observer
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK: simulation.spawn @held
module {
  simulation.design @implicit_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "held"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %state : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
  }
}

// -----

!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @counter_observer
// CHECK-NOT: __talos_region_kernel_
// CHECK: simulation.spawn @producer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @held
// CHECK-NOT: __talos_region_kernel_
module {
  simulation.design @counter_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "held"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %old = simulation.ref.load %state : !r -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %state : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
  }
}

// -----

!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @snapshot_observer
// CHECK-NOT: __talos_region_kernel_
// CHECK: simulation.spawn @producer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @held
// CHECK-NOT: __talos_region_kernel_
module {
  simulation.design @snapshot_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "held"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %old = simulation.ref.load %state : !r -> i8
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %state : i8, !r
      cf.br ^wait
    ^wait:
      simulation.ref.store %old to %other : i8, !r
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
  }
}

// -----

!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @opaque_observer
// CHECK-NOT: __talos_region_kernel_
// CHECK: simulation.spawn @producer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @held
// CHECK-NOT: __talos_region_kernel_
module {
  simulation.design @opaque_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "held"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @sample(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %state : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
    simulation.func @sample(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %state = simulation.context.storage %ctx[4] : !r
      %count = simulation.context.storage %ctx[7] : !r
      cf.br ^wait
    ^wait:
      simulation.suspend.change %state to ^body : !r
    ^body:
      %old = simulation.ref.load %count : !r -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %count : i8, !r
      cf.br ^wait
    }
  }
}

// -----

!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @continuous_observer
// CHECK-NOT: __talos_region_kernel_
// CHECK: simulation.spawn @producer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @held
// CHECK-NOT: __talos_region_kernel_
module {
  simulation.design @continuous_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "held"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %state : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
  }
}

// -----

!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @alias_observer
// CHECK-NOT: __talos_region_kernel_
// CHECK: simulation.spawn @producer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @held
// CHECK-NOT: __talos_region_kernel_
module {
  simulation.design @alias_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "held"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %value = simulation.ref.load %input : !r -> i8
      %zero = arith.constant 0 : i8
      %selector = arith.cmpi slt, %value, %zero : i8
      %selected = arith.select %selector, %state, %other : !r
      simulation.ref.store %value to %selected : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
  }
}

// -----

!r = !simulation.ref<i8>
!f = !simulation.ref<i1>
// CHECK-LABEL: simulation.design @shared_writer_observer
// CHECK-NOT: __talos_region_kernel_
// CHECK: simulation.spawn @producer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @held
// CHECK-NOT: __talos_region_kernel_
module {
  simulation.design @shared_writer_observer {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 1 continuous hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "held"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @held(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %request = simulation.context.storage %ctx[3] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %r = simulation.ref.load %response : !r -> i8
      simulation.ref.store %r to %output : i8, !r
      %i = simulation.ref.load %input : !r -> i8
      simulation.ref.store %i to %request : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[3] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %i = simulation.ref.load %request : !r -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %i, %one : i8
      simulation.ref.store %r to %response : i8, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @held(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[5] : !r
      %enable = simulation.context.storage %ctx[1] : !f
      %state = simulation.context.storage %ctx[4] : !r
      %other = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %flag = simulation.ref.load %enable : !f -> i1
      cf.cond_br %flag, ^update, ^wait
    ^update:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %state : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %enable edges [0, 0] to ^body : !r, !f
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %state = simulation.context.storage %ctx[4] : !r
      %zero = arith.constant 0 : i8
      %one = simulation.time.constant 1
      simulation.suspend.delay %one to ^write
    ^write:
      simulation.ref.store %zero to %state : i8, !r
      simulation.return
    }
  }
}
