// RUN: talos-opt %s --test-talos-activation-memory='ordering=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=ORDER
// RUN: talos-opt %s --test-talos-activation-memory -o /dev/null 2>&1 | FileCheck %s --check-prefix=STRICT

// The display sees the packed value after both branches have assigned the
// low nibble. The high nibble still depends on the incoming value on one
// path. Every execution of the report remains observable (1800-2023 4.6,
// 9.4.2, 20.10). A storage footprint alone cannot authorize repetition.
// ORDER: activation @report valid=1 complete=0
// ORDER-NEXT: live-in s0[4,8) s1[0,1)
// ORDER-NEXT: must-write s0[0,4)
// ORDER-NEXT: may-write s0[0,8)
// STRICT: activation @report valid=0
module {
  simulation.design @reporting {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "report"
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %data = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %flag = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %low = simulation.ref.extract %data from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %value = arith.constant 3 : i4
      %word = arith.constant 16 : i8
      %enabled = simulation.ref.load %flag : !simulation.ref<i1> -> i1
      cf.cond_br %enabled, ^whole, ^partial
    ^whole:
      simulation.ref.store %word to %data : i8, !simulation.ref<i8>
      cf.br ^show
    ^partial:
      simulation.ref.store %value to %low : i4, !simulation.ref<i4>
      cf.br ^show
    ^show:
      %arg = simulation.ref.load %data : !simulation.ref<i8> -> i8
      %out = arith.constant 1 : i32
      %time = simulation.time.now %ctx
      simulation.display %ctx to %out(%time, %arg) newline = true radix = <decimal> flags = [0, 0] : i64, i8
      simulation.error %ctx
      simulation.return
    }
  }
}
