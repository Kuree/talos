// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{max-members=2 grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --test-talos-activation-regions='functions=request reaching-values=true inputs=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=INPUTS

// IEEE 1800-2023 4.3/4.6/9.4.2: ordering depends on every publication,
// including overwritten intermediate values. A whole-byte load used only
// through its low nibble does not depend on the upper-nibble writer. The
// repeated output makes @request nonrepeatable, so its source waits must
// remain. A false third member would exceed the two-member fusion budget.
// The wide physical load models a lowered packed access; its explicit wait
// records the source sensitivity before widening.
// CHECK-LABEL: simulation.design @unused_loaded_lanes
// CHECK: simulation.func @root
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK-NEXT: {{.*}}simulation.spawn @upper
// CHECK-NEXT: simulation.return
// CHECK-LABEL: simulation.func @upper(
// CHECK: %[[UPPER_INPUT:[0-9]+]] = simulation.context.storage %{{.*}}[1]
// CHECK: simulation.suspend.change %[[UPPER_INPUT]] to
// CHECK-LABEL: simulation.func private @__talos_region_kernel_0_0(
// CHECK: %[[INPUT:[0-9]+]] = simulation.context.storage %{{.*}}[0]
// CHECK: %[[LOW:[0-9]+]] = simulation.ref.extract %[[INPUT]] from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
// CHECK: simulation.suspend.any %[[LOW]] edges [0] to
// INPUTS-LABEL: regions @request valid=1
// INPUTS: live-in s0[0,8) s2[0,8)
// INPUTS: value-input s0[0,4) s2[0,8)
module {
  simulation.design @unused_loaded_lanes {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "request"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "bank"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "upper"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @request(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @bank(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @upper(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @request(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %low = simulation.ref.extract %input from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %response = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %whole = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %nibble = arith.trunci %whole : i8 to i4
      %request = arith.extui %nibble : i4 to i8
      %zero = arith.constant 0 : i8
      simulation.ref.store %zero to %output : i8, !simulation.ref<i8>
      %answer = simulation.ref.load %response : !simulation.ref<i8> -> i8
      simulation.ref.store %answer to %output : i8, !simulation.ref<i8>
      simulation.ref.store %request to %address : i8, !simulation.ref<i8>
      simulation.suspend.any %low, %response edges [0, 0] to ^body : !simulation.ref<i4>, !simulation.ref<i8>
    }
    simulation.func @bank(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %response = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %result = arith.addi %value, %one : i8
      simulation.ref.store %result to %response : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @upper(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %storage = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %high = simulation.ref.extract %storage from 4 : !simulation.ref<i8> -> !simulation.ref<i4>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %nibble = arith.trunci %value : i8 to i4
      simulation.ref.store %nibble to %high : i4, !simulation.ref<i4>
      simulation.suspend.change %input to ^body : !simulation.ref<i8>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @intermediate_loaded_lanes
// CHECK: simulation.func @root
// An intermediate upper-lane publication retains the dependency.
// CHECK: simulation.spawn @request
// CHECK-NEXT: {{.*}}simulation.spawn @bank
// CHECK-NEXT: {{.*}}simulation.spawn @upper
// CHECK-NEXT: simulation.return
// CHECK-NOT: simulation.spawn @__talos_region_kernel_
// INPUTS-LABEL: regions @request valid=1
// INPUTS: value-input s0[0,8) s2[0,8)
// INPUTS-NEXT: final-input s0[0,4) s2[0,8)
module {
  simulation.design @intermediate_loaded_lanes {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "request"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "bank"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "upper"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @request(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @bank(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @upper(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @request(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %low = simulation.ref.extract %input from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %response = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %whole = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %nibble = arith.trunci %whole : i8 to i4
      %request = arith.extui %nibble : i4 to i8
      %zero = arith.constant 0 : i8
      simulation.ref.store %whole to %output : i8, !simulation.ref<i8>
      %answer = simulation.ref.load %response : !simulation.ref<i8> -> i8
      simulation.ref.store %answer to %output : i8, !simulation.ref<i8>
      simulation.ref.store %request to %address : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @bank(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %response = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %result = arith.addi %value, %one : i8
      simulation.ref.store %result to %response : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @upper(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %storage = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %high = simulation.ref.extract %storage from 4 : !simulation.ref<i8> -> !simulation.ref<i4>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %nibble = arith.trunci %value : i8 to i4
      simulation.ref.store %nibble to %high : i4, !simulation.ref<i4>
      simulation.suspend.change %input to ^body : !simulation.ref<i8>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @explicit_unused_watch
// CHECK: simulation.func @root
// An uncertified unused source watch retains the event dependency.
// CHECK: simulation.spawn @request
// CHECK-NEXT: {{.*}}simulation.spawn @bank
// CHECK-NEXT: {{.*}}simulation.spawn @upper
// CHECK-NEXT: simulation.return
// CHECK-NOT: simulation.spawn @__talos_region_kernel_
// INPUTS-LABEL: regions @request valid=1
// INPUTS: value-input s0[0,4) s2[0,8)
module {
  simulation.design @explicit_unused_watch {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "request"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "bank"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "upper"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @request(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @bank(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @upper(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @request(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %low = simulation.ref.extract %input from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %response = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %whole = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %nibble = arith.trunci %whole : i8 to i4
      %request = arith.extui %nibble : i4 to i8
      %zero = arith.constant 0 : i8
      simulation.ref.store %zero to %output : i8, !simulation.ref<i8>
      %answer = simulation.ref.load %response : !simulation.ref<i8> -> i8
      simulation.ref.store %answer to %output : i8, !simulation.ref<i8>
      simulation.ref.store %request to %address : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @bank(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %response = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %result = arith.addi %value, %one : i8
      simulation.ref.store %result to %response : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @upper(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %storage = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %high = simulation.ref.extract %storage from 4 : !simulation.ref<i8> -> !simulation.ref<i4>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %nibble = arith.trunci %value : i8 to i4
      simulation.ref.store %nibble to %high : i4, !simulation.ref<i4>
      simulation.suspend.change %input to ^body : !simulation.ref<i8>
    }
  }
}
