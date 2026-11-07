// RUN: talos-opt %s --split-input-file --test-talos-activation-regions='components=true reaching-values=true' -o /dev/null 2>&1 | FileCheck %s

// IEEE 1800-2023 4.3/4.6/10.4.1: a whole integer or packed integer copy
// participates in an artificial owner cycle when a later actor writes only
// independent source lanes. Split only cyclic copy publications, retaining
// the original computation and preserving genuine feedback in the same lane.
// CHECK-LABEL: regions @copy valid=1
// CHECK: slice components: valid nodes=5 components=5 cyclic=0 events=3
!value = i4
module {
  simulation.design @integer_copy {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !value design
    simulation.storage.decl 1 in 0 : !value design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "copy"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "writer"
    simulation.func @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<!value> -> !value
      simulation.ref.store %value to %output : !value, !simulation.ref<!value>
      simulation.suspend.change %input to ^body : !simulation.ref<!value>
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %whole = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      %input = simulation.ref.extract %whole from 0 : !simulation.ref<!value> -> !simulation.ref<i1>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %whole = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.ref.extract %whole from 3 : !simulation.ref<!value> -> !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
  }
}

// -----

// CHECK-LABEL: regions @copy valid=1
// CHECK: slice components: valid nodes=5 components=5 cyclic=0 events=3
!value = !simulation.packed_array<3 : 0 x i1>
module {
  simulation.design @packed_integer_copy {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !value design
    simulation.storage.decl 1 in 0 : !value design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "copy"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "writer"
    simulation.func @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<!value> -> !value
      simulation.ref.store %value to %output : !value, !simulation.ref<!value>
      simulation.suspend.change %input to ^body : !simulation.ref<!value>
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %whole = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      %input = simulation.ref.extract %whole from 0 : !simulation.ref<!value> -> !simulation.ref<i1>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %whole = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.ref.extract %whole from 3 : !simulation.ref<!value> -> !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
  }
}

// -----

// CHECK-LABEL: regions @copy valid=1
// CHECK: slice components: valid nodes=6 components=6 cyclic=0 events=3
!value = i130
module {
  simulation.design @wide_integer_copy {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !value design
    simulation.storage.decl 1 in 0 : !value design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "copy"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "writer"
    simulation.func @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<!value> -> !value
      simulation.ref.store %value to %output : !value, !simulation.ref<!value>
      simulation.suspend.change %input to ^body : !simulation.ref<!value>
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %whole = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      %input = simulation.ref.extract %whole from 65 : !simulation.ref<!value> -> !simulation.ref<i1>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %whole = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.ref.extract %whole from 129 : !simulation.ref<!value> -> !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
  }
}

// -----

// CHECK-LABEL: regions @copy valid=1
// CHECK: slice components: valid nodes=4 components=2 cyclic=1 events=3
!value = i4
module {
  simulation.design @integer_feedback {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !value design
    simulation.storage.decl 1 in 0 : !value design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "copy"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "writer"
    simulation.func @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<!value> -> !value
      simulation.ref.store %value to %output : !value, !simulation.ref<!value>
      simulation.suspend.change %input to ^body : !simulation.ref<!value>
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %whole = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      %input = simulation.ref.extract %whole from 0 : !simulation.ref<!value> -> !simulation.ref<i1>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %whole = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %output = simulation.ref.extract %whole from 0 : !simulation.ref<!value> -> !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
  }
}
