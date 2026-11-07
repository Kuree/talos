// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{max-members=2 grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// IEEE 1800-2023 4.3, 4.6, 9.2.2.2.1: the original broad waits remain in the
// source program. A complete, exclusive single-publication observer cannot
// expose a change outside its live input lanes. The planner and materializer
// may therefore omit that dead event edge when scheduling the statement DAG.
// The two-member limit makes the false third dependency block fusion unless
// both the cohort graph and complete contraction graph use the refined edge.
// CHECK-LABEL: simulation.design @dead_watch
// CHECK: simulation.func @root
// CHECK-NOT: simulation.spawn @producer_and_consumer
// CHECK-NOT: simulation.spawn @transform
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK: simulation.spawn @overwrite
// CHECK: simulation.return
// CHECK: simulation.func @overwrite
// CHECK: %[[INPUT:[0-9]+]] = simulation.context.storage %{{.*}}[0]
// CHECK: %[[EXTRA:[0-9]+]] = simulation.context.storage %{{.*}}[2]
// CHECK: simulation.suspend.any %[[INPUT]], %[[EXTRA]] edges [0, 0]
module {
  simulation.design @dead_watch {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %new = simulation.ref.load %input : !simulation.ref<i8> -> i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
  }
}

// -----
// CHECK-LABEL: simulation.design @control_watch
// CHECK: simulation.func @root
// A control dependency, repeated transition, or no-live-input fallback
// preserves all source watches and the original three owners.
// CHECK: simulation.spawn @producer_and_consumer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @overwrite
// CHECK-NOT: simulation.spawn @__talos_region_kernel
// CHECK: simulation.return
module {
  simulation.design @control_watch {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %base = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %control = simulation.ref.load %extra : !simulation.ref<i8> -> i8
      %zero_watch = arith.constant 0 : i8
      %enabled = arith.cmpi ne, %control, %zero_watch : i8
      %new = arith.select %enabled, %base, %zero_watch : i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
  }
}

// -----
// CHECK-LABEL: simulation.design @repeated_watch
// CHECK: simulation.func @root
// A control dependency, repeated transition, or no-live-input fallback
// preserves all source watches and the original three owners.
// CHECK: simulation.spawn @producer_and_consumer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @overwrite
// CHECK-NOT: simulation.spawn @__talos_region_kernel
// CHECK: simulation.return
module {
  simulation.design @repeated_watch {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %new = simulation.ref.load %input : !simulation.ref<i8> -> i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      %zero_watch = arith.constant 0 : i8
      simulation.ref.store %zero_watch to %output : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
  }
}

// -----
// CHECK-LABEL: simulation.design @constant_watch
// CHECK: simulation.func @root
// A control dependency, repeated transition, or no-live-input fallback
// preserves all source watches and the original three owners.
// CHECK: simulation.spawn @producer_and_consumer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @overwrite
// CHECK-NOT: simulation.spawn @__talos_region_kernel
// CHECK: simulation.return
module {
  simulation.design @constant_watch {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %new = arith.constant 7 : i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
  }
}

// -----
// CHECK-LABEL: simulation.design @dead_packed_lane
// CHECK: simulation.func @root
// A producer writes only the dead high nibble. The whole consumed watch
// still contains live low bits, so watch/input overlap alone cannot cut it.
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK: simulation.spawn @overwrite
// CHECK: simulation.return
module {
  simulation.design @dead_packed_lane {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      %part = simulation.ref.extract %result from 4 : !simulation.ref<i8> -> !simulation.ref<i4>
      %nibble = arith.trunci %r : i8 to i4
      simulation.ref.store %nibble to %part : i4, !simulation.ref<i4>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %base = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %low_ref = simulation.ref.extract %extra from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %low = simulation.ref.load %low_ref : !simulation.ref<i4> -> i4
      %extended = arith.extui %low : i4 to i8
      %new = arith.addi %base, %extended : i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
  }
}

// -----
// CHECK-LABEL: simulation.design @live_packed_lane
// CHECK: simulation.func @root
// Moving the write to the live nibble restores the actual dependency.
// CHECK: simulation.spawn @producer_and_consumer
// CHECK: simulation.spawn @transform
// CHECK: simulation.spawn @overwrite
// CHECK-NOT: simulation.spawn @__talos_region_kernel
// CHECK: simulation.return
module {
  simulation.design @live_packed_lane {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      %part = simulation.ref.extract %result from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %nibble = arith.trunci %r : i8 to i4
      simulation.ref.store %nibble to %part : i4, !simulation.ref<i4>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %base = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %low_ref = simulation.ref.extract %extra from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %low = simulation.ref.load %low_ref : !simulation.ref<i4> -> i4
      %extended = arith.extui %low : i4 to i8
      %new = arith.addi %base, %extended : i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
  }
}
