// RUN: talos-opt %s --canonicalize -o %t.canonical.mlir
// RUN: FileCheck %s --check-prefix=FOLD < %t.canonical.mlir
// RUN: talos-opt %t.canonical.mlir '--test-talos-activation-regions=verify-prepared-views=true inputs=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: diff %t.canonical.mlir %t.analyzed

// A loop limit read from an elaborated packed configuration constant folds to
// a scalar before the finite-induction proof (IEEE 1800-2023 7.2.1 layout,
// 12.7.1 loop). Analysis is read-only. Accepted: the bound field alone
// decides, even with unknown bits in neighbours or beyond 64 bits. Rejected
// (termination): a mutable bound, and a bound whose induction wraps.
!array = !simulation.unpacked_array<0 : 7 x i8>
!aref = !simulation.ref<!array>
!cfg = !simulation.packed_struct<[
  #simulation.field<name = "high", type = !simulation.logic<4>, ordinal = 0, packedOffset = 36>,
  #simulation.field<name = "depth", type = i32, ordinal = 1, packedOffset = 4>,
  #simulation.field<name = "low", type = !simulation.logic<4>, ordinal = 2, packedOffset = 0>
]>
!wide_cfg = !simulation.packed_struct<[
  #simulation.field<name = "high", type = !simulation.logic<68>, ordinal = 0, packedOffset = 132>,
  #simulation.field<name = "depth", type = i32, ordinal = 1, packedOffset = 100>,
  #simulation.field<name = "low", type = !simulation.logic<100>, ordinal = 2, packedOffset = 0>
]>
!wrap_cfg = !simulation.packed_struct<[
  #simulation.field<name = "high", type = !simulation.logic<1>, ordinal = 0, packedOffset = 3>,
  #simulation.field<name = "depth", type = i3, ordinal = 1, packedOffset = 0>
]>
module {
  simulation.design @packed_bounds {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !array design
    simulation.storage.decl 1 in 0 : !array design
    simulation.storage.decl 2 in 0 : !simulation.logic<40> design
    // CHECK-LABEL: regions @unknown_neighbors valid=1
    // CHECK: must-write s1[0,64)
    // FOLD-LABEL: simulation.func @unknown_neighbors(
    // FOLD: arith.constant 8 : i32
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "top.unknown_neighbors"
    simulation.func @unknown_neighbors(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %src = simulation.context.storage %ctx[0] : !aref
      %dst = simulation.context.storage %ctx[1] : !aref
      %bits = simulation.logic.constant 128 : i40, 1030792151055 : i40 : !simulation.logic<40>
      %zero = arith.constant 0 : i32
      %step = arith.constant 1 : i32
      %fill = arith.constant 0 : i8
      cf.br ^loop(%zero : i32)
    ^loop(%i: i32):
      %cfg = simulation.packed.unflatten %bits : (!simulation.logic<40>) -> !cfg
      %bound = simulation.aggregate.extract %cfg[1] : (!cfg) -> i32
      %more = arith.cmpi ult, %i, %bound : i32
      cf.cond_br %more, ^copy, ^wait
    ^copy:
      %to = simulation.ref.array_element %dst[%i] : (!aref, i32) -> !simulation.ref<i8>
      simulation.ref.store %fill to %to : i8, !simulation.ref<i8>
      %next = arith.addi %i, %step : i32
      cf.br ^loop(%next : i32)
    ^wait:
      simulation.suspend.change %src to ^resume : !aref
    ^resume:
      cf.br ^loop(%zero : i32)
    }
    // CHECK-LABEL: regions @wide_bound valid=1
    // CHECK: must-write s1[0,64)
    // FOLD-LABEL: simulation.func @wide_bound(
    // FOLD: arith.constant 8 : i32
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "top.wide_bound"
    simulation.func @wide_bound(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %src = simulation.context.storage %ctx[0] : !aref
      %dst = simulation.context.storage %ctx[1] : !aref
      %bits = simulation.logic.constant 10141204801825835211973625643008 : i200, 0 : i200 : !simulation.logic<200>
      %zero = arith.constant 0 : i32
      %step = arith.constant 1 : i32
      %fill = arith.constant 0 : i8
      cf.br ^loop(%zero : i32)
    ^loop(%i: i32):
      %cfg = simulation.packed.unflatten %bits : (!simulation.logic<200>) -> !wide_cfg
      %bound = simulation.aggregate.extract %cfg[1] : (!wide_cfg) -> i32
      %more = arith.cmpi ult, %i, %bound : i32
      cf.cond_br %more, ^copy, ^wait
    ^copy:
      %to = simulation.ref.array_element %dst[%i] : (!aref, i32) -> !simulation.ref<i8>
      simulation.ref.store %fill to %to : i8, !simulation.ref<i8>
      %next = arith.addi %i, %step : i32
      cf.br ^loop(%next : i32)
    ^wait:
      simulation.suspend.change %src to ^resume : !aref
    ^resume:
      cf.br ^loop(%zero : i32)
    }
    // CHECK-LABEL: regions @mutable_bound valid=0 reason=termination
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "top.mutable_bound"
    simulation.func @mutable_bound(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %src = simulation.context.storage %ctx[0] : !aref
      %dst = simulation.context.storage %ctx[1] : !aref
      %parameter = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<40>>
      %zero = arith.constant 0 : i32
      %step = arith.constant 1 : i32
      %fill = arith.constant 0 : i8
      cf.br ^loop(%zero : i32)
    ^loop(%i: i32):
      %bits = simulation.ref.load %parameter : !simulation.ref<!simulation.logic<40>> -> !simulation.logic<40>
      %cfg = simulation.packed.unflatten %bits : (!simulation.logic<40>) -> !cfg
      %bound = simulation.aggregate.extract %cfg[1] : (!cfg) -> i32
      %more = arith.cmpi ult, %i, %bound : i32
      cf.cond_br %more, ^copy, ^wait
    ^copy:
      %to = simulation.ref.array_element %dst[%i] : (!aref, i32) -> !simulation.ref<i8>
      simulation.ref.store %fill to %to : i8, !simulation.ref<i8>
      %next = arith.addi %i, %step : i32
      cf.br ^loop(%next : i32)
    ^wait:
      simulation.suspend.any %src, %parameter edges [0, 0] to ^resume : !aref, !simulation.ref<!simulation.logic<40>>
    ^resume:
      cf.br ^loop(%zero : i32)
    }
    // CHECK-LABEL: regions @wrapping_bound valid=0 reason=termination
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "top.wrapping_bound"
    simulation.func @wrapping_bound(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      %src = simulation.context.storage %ctx[0] : !aref
      %dst = simulation.context.storage %ctx[1] : !aref
      %bits = simulation.logic.constant 7 : i4, 0 : i4 : !simulation.logic<4>
      %zero = arith.constant 0 : i3
      %step = arith.constant 2 : i3
      %fill = arith.constant 0 : i8
      cf.br ^loop(%zero : i3)
    ^loop(%i: i3):
      %cfg = simulation.packed.unflatten %bits : (!simulation.logic<4>) -> !wrap_cfg
      %bound = simulation.aggregate.extract %cfg[1] : (!wrap_cfg) -> i3
      %more = arith.cmpi ult, %i, %bound : i3
      cf.cond_br %more, ^copy, ^wait
    ^copy:
      %to = simulation.ref.array_element %dst[%i] : (!aref, i3) -> !simulation.ref<i8>
      simulation.ref.store %fill to %to : i8, !simulation.ref<i8>
      %next = arith.addi %i, %step : i3
      cf.br ^loop(%next : i3)
    ^wait:
      simulation.suspend.change %src to ^resume : !aref
    ^resume:
      cf.br ^loop(%zero : i3)
    }
  }
}
