// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// IEEE 1800-2023 4.3/4.6/9.4.2: observer admission is a property of the
// complete section. B has repeated publications observed by A and @observer.
// The observer has its own external input, but must join the producer to
// close its intermediate events. The connected cohort also contains actual
// feedback C/D, so its publication schedule fails. Recover A/B/@observer
// together; rejecting B alone would lose their valid DAG. Keep C/D on their
// original executors and preserve the existing independent fused kernel.
// An opaque outside observer still forbids A/B.
// CHECK-LABEL: simulation.design @closed_observers
// CHECK: simulation.func @root
// CHECK: simulation.spawn @already_kernel
// CHECK-NEXT: {{.*}}simulation.spawn @__talos_region_kernel_0_0
// CHECK-NEXT: {{.*}}simulation.spawn @c
// CHECK-NEXT: {{.*}}simulation.spawn @d
// CHECK-NEXT: simulation.return
// CHECK-LABEL: simulation.func private @already_kernel(
!r = !simulation.ref<i8>
module {
  simulation.design @closed_observers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.storage.decl 8 in 0 : i8 design
    simulation.storage.decl 9 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "c"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "d"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "already_kernel"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "observer"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %old = simulation.spawn @already_kernel(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @c(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @d(%ctx) : !simulation.context -> !simulation.process
      %observer = simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process

      simulation.return
    }
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %i = simulation.context.storage %ctx[0] : !r
      %address = simulation.context.storage %ctx[1] : !r
      %bank = simulation.context.storage %ctx[2] : !r
      %output = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %result = simulation.ref.load %bank : !r -> i8
      simulation.ref.store %result to %output : i8, !r
      %input = simulation.ref.load %i : !r -> i8
      simulation.ref.store %input to %address : i8, !r
      simulation.suspend.any %i, %bank edges [0, 0] to ^body : !r, !r
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %bank = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      %zero = arith.constant 0 : i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %zero to %bank : i8, !r
      simulation.ref.store %next to %bank : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
    simulation.func @c(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %previous = simulation.context.storage %ctx[5] : !r
      %output = simulation.context.storage %ctx[4] : !r
      cf.br ^body
    ^body:
      %x = simulation.ref.load %previous : !r -> i8
      %y = simulation.ref.load %address : !r -> i8
      %value = arith.andi %x, %y : i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.any %address, %previous edges [0, 0] to ^body : !r, !r
    }
    simulation.func @d(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.storage %ctx[4] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %bank = simulation.context.storage %ctx[2] : !r
      %other = simulation.context.storage %ctx[8] : !r
      %output = simulation.context.storage %ctx[9] : !r
      cf.br ^body
    ^body:
      %b = simulation.ref.load %bank : !r -> i8
      %x = simulation.ref.load %other : !r -> i8
      %value = arith.xori %b, %x : i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.any %bank, %other edges [0, 0] to ^body : !r, !r
    }
    simulation.func private @already_kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64, schedule.native.region_body} {
      %input = simulation.context.storage %ctx[6] : !r
      %output = simulation.context.storage %ctx[7] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }

  }
}

// -----

// CHECK-LABEL: simulation.design @outside_observer
// CHECK: simulation.func @root
// CHECK: simulation.spawn @already_kernel
// CHECK-NEXT: {{.*}}simulation.spawn @a
// CHECK-NEXT: {{.*}}simulation.spawn @b
// CHECK-NEXT: {{.*}}simulation.spawn @c
// CHECK-NEXT: {{.*}}simulation.spawn @d
// CHECK-NEXT: {{.*}}simulation.spawn @observer
// CHECK-NEXT: {{.*}}simulation.spawn @opaque
// CHECK-NOT: simulation.spawn @__talos_region_kernel_
// CHECK-NEXT: simulation.return
// CHECK-LABEL: simulation.func private @already_kernel(
!r = !simulation.ref<i8>
module {
  simulation.design @outside_observer {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.storage.decl 8 in 0 : i8 design
    simulation.storage.decl 9 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "c"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "d"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "already_kernel"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "observer"
    simulation.code_unit.decl 6 in 0 always hierarchy "opaque"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %old = simulation.spawn @already_kernel(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @c(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @d(%ctx) : !simulation.context -> !simulation.process
      %observer = simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process
      %opaque = simulation.spawn @opaque(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %i = simulation.context.storage %ctx[0] : !r
      %address = simulation.context.storage %ctx[1] : !r
      %bank = simulation.context.storage %ctx[2] : !r
      %output = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %result = simulation.ref.load %bank : !r -> i8
      simulation.ref.store %result to %output : i8, !r
      %input = simulation.ref.load %i : !r -> i8
      simulation.ref.store %input to %address : i8, !r
      simulation.suspend.any %i, %bank edges [0, 0] to ^body : !r, !r
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %bank = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      %zero = arith.constant 0 : i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %zero to %bank : i8, !r
      simulation.ref.store %next to %bank : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
    simulation.func @c(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %previous = simulation.context.storage %ctx[5] : !r
      %output = simulation.context.storage %ctx[4] : !r
      cf.br ^body
    ^body:
      %x = simulation.ref.load %previous : !r -> i8
      %y = simulation.ref.load %address : !r -> i8
      %value = arith.andi %x, %y : i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.any %address, %previous edges [0, 0] to ^body : !r, !r
    }
    simulation.func @d(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.storage %ctx[4] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %bank = simulation.context.storage %ctx[2] : !r
      %other = simulation.context.storage %ctx[8] : !r
      %output = simulation.context.storage %ctx[9] : !r
      cf.br ^body
    ^body:
      %b = simulation.ref.load %bank : !r -> i8
      %x = simulation.ref.load %other : !r -> i8
      %value = arith.xori %b, %x : i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.any %bank, %other edges [0, 0] to ^body : !r, !r
    }
    simulation.func private @already_kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64, schedule.native.region_body} {
      %input = simulation.context.storage %ctx[6] : !r
      %output = simulation.context.storage %ctx[7] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
    simulation.func @opaque(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 6 : i64} {
      %bank = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %bank : !r -> i8
      %format = simulation.bytes.constant "bank %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%format, %value) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      simulation.suspend.change %bank to ^body : !r
    }
  }
}
