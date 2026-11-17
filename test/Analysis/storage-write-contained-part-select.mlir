// RUN: talos-opt %s --test-talos-storage-writes -o /dev/null 2>&1 | FileCheck %s

// w[0][idx +: 2] on `logic [1:0][7:0] w`. A part-select of the fixed element
// w[0] reaching past bit 7 would write only the in-range bits (IEEE 1800-2023
// 11.5.1), so a direct store into the whole root would have to clip at the
// element, not at the root. Where the index is proven to lie in [0, 6] the
// selection is contained in w[0] and needs no clipping: its write is direct.
// Without that proof it is not.
// CHECK-LABEL: function contained
// CHECK-NEXT: write 0 once=1 root=0 bits=16 lane=0:2 stride=1 dynamic=1 clipped=1 fixed=0 direct=1
// CHECK-LABEL: function unproved
// CHECK-NEXT: write 0 once=1 root=0 bits=16 lane=0:2 stride=1 dynamic=1 clipped=1 fixed=0 direct=0
module {
  simulation.design @writes {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "contained"
    simulation.code_unit.decl 2 in 0 function hierarchy "unproved"
    simulation.storage.decl 0 in 0 : i16 design
    simulation.func @contained(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %index: i3 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !simulation.ref<i16>
      %element = simulation.ref.extract %root from 0 : !simulation.ref<i16> -> !simulation.ref<i8>
      %low = arith.extui %index : i3 to i8
      %six = arith.constant 6 : i8
      %fits = arith.cmpi sle, %low, %six : i8
      cf.cond_br %fits, ^write, ^done
    ^write:
      %selected = simulation.ref.dyn_extract %element from %low : (!simulation.ref<i8>, i8) -> !simulation.ref<i2>
      %ones = arith.constant -1 : i2
      simulation.ref.store %ones to %selected : i2, !simulation.ref<i2>
      cf.br ^done
    ^done:
      simulation.return
    }
    simulation.func @unproved(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %index: i3 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %root = simulation.context.storage %ctx[0] : !simulation.ref<i16>
      %element = simulation.ref.extract %root from 0 : !simulation.ref<i16> -> !simulation.ref<i8>
      %low = arith.extui %index : i3 to i8
      %selected = simulation.ref.dyn_extract %element from %low : (!simulation.ref<i8>, i8) -> !simulation.ref<i2>
      %ones = arith.constant -1 : i2
      simulation.ref.store %ones to %selected : i2, !simulation.ref<i2>
      simulation.return
    }
  }
}
