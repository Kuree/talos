// RUN: talos-opt %s -split-input-file '--test-talos-activation-regions=functions=first,second,a,b,c,d verify-prepared-views=true canonical-controls=true reaching-values=true publications=true rearm-interleaving=true interleaving=true order=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -split-input-file -o %t.original
// RUN: diff %t.original %t.analyzed
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.lowered
// RUN: FileCheck %s --check-prefix=LOWER < %t.lowered

// Re-arm plans for two-process pulse cycles whose witness holds. Each plan
// breaks the cycle with an active preemption on the chosen owners; the
// original publications and waits remain.

// 2-state guards: integer compare, zext to 65 bits, trunc and XOR. The
// witness binds the index to 1 and the selected array bit to the XOR
// condition, not to an arbitrary member of the may-read range.
// CHECK: rearm plan: handoffs=2 preemptions= @first
// LOWER-LABEL: design @integer_index_guards
// LOWER-LABEL: simulation.func @first(
// LOWER: simulation.suspend.delay
// LOWER-SAME: resume_region = 2 : i32
!bit = i1
!ref = !simulation.ref<!bit>
!flags = !simulation.packed_array<1 : 0 x !bit>
module attributes {llvm.data_layout = "e-i64:64"} {
  simulation.design @integer_index_guards {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !flags design
    simulation.storage.decl 3 in 0 : !flags design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : i2 design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "loop.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "loop.second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %flags = simulation.context.storage %ctx[2] : !simulation.ref<!flags>
      %copy = simulation.context.storage %ctx[3] : !simulation.ref<!flags>
      %enable = simulation.context.storage %ctx[4] : !ref
      %index = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      %saved = simulation.context.storage %ctx[6] : !ref
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %y : !bit, !ref
      %idx = simulation.ref.load %index : !simulation.ref<i2> -> i2
      %three = arith.constant 1 : i2
      %is_three = arith.cmpi eq, %idx, %three : i2
      cf.cond_br %is_three, ^set, ^join
    ^set:
      simulation.ref.store %one to %y : !bit, !ref
      cf.br ^join
    ^join:
      %old = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      simulation.suspend.any %x, %flags, %enable, %index edges [0, 0, 0, 0] to ^body : !ref, !simulation.ref<!flags>, !ref, !simulation.ref<i2>
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %flags = simulation.context.storage %ctx[2] : !simulation.ref<!flags>
      %enable = simulation.context.storage %ctx[4] : !ref
      %index = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      %saved = simulation.context.storage %ctx[7] : !ref
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %x : !bit, !ref
      %idx = simulation.ref.load %index : !simulation.ref<i2> -> i2
      %wide = arith.extui %idx : i2 to i65
      %selected = simulation.ref.array_element %flags[%wide] : (!simulation.ref<!flags>, i65) -> !ref
      %flag = simulation.ref.load %selected : !ref -> !bit
      %index_lsb = arith.trunci %idx : i2 to i1
      %test = arith.xori %flag, %index_lsb : i1
      cf.cond_br %test, ^set, ^join
    ^set:
      simulation.ref.store %one to %x : !bit, !ref
      cf.br ^join
    ^join:
      %old = simulation.ref.load %y : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      simulation.suspend.any %y, %flags, %index, %enable edges [0, 0, 0, 0] to ^body : !ref, !simulation.ref<!flags>, !simulation.ref<i2>, !ref
    }
  }
}

// -----
// A proved finite copy loop does not make a later conditional unreachable.
// A completed diamond with an unsupported condition constrains nothing, and a
// known-false AND operand suffices with an unsupported other operand. The
// dynamic packed-array selector is bound to a valid index and its bit.
// CHECK: rearm plan: handoffs=2 preemptions= @first
// LOWER-LABEL: design @finite_loop_guards
// LOWER-LABEL: simulation.func @first(
// LOWER: simulation.suspend.delay
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
!flags = !simulation.packed_array<1 : 0 x !bit>
module attributes {llvm.data_layout = "e-i64:64"} {
  simulation.design @finite_loop_guards {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !flags design
    simulation.storage.decl 3 in 0 : !flags design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !simulation.logic<2> design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "loop.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "loop.second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %flags = simulation.context.storage %ctx[2] : !simulation.ref<!flags>
      %copy = simulation.context.storage %ctx[3] : !simulation.ref<!flags>
      %enable = simulation.context.storage %ctx[4] : !ref
      %index = simulation.context.storage %ctx[5] : !simulation.ref<!simulation.logic<2>>
      %saved = simulation.context.storage %ctx[6] : !ref
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %y : !bit, !ref
      cf.br ^loop(%c0 : i32)
    ^loop(%i: i32):
      %more = arith.cmpi ult, %i, %c2 : i32
      cf.cond_br %more, ^copy, ^after
    ^copy:
      %from = simulation.ref.array_element %flags[%i] : (!simulation.ref<!flags>, i32) -> !ref
      %to = simulation.ref.array_element %copy[%i] : (!simulation.ref<!flags>, i32) -> !ref
      %value = simulation.ref.load %from : !ref -> !bit
      simulation.ref.store %value to %to : !bit, !ref
      %next = arith.addi %i, %c1 : i32
      cf.br ^loop(%next : i32)
    ^after:
      %idx = simulation.ref.load %index : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %bits = simulation.logic.to_bits %idx : !simulation.logic<2> -> i2
      %square = arith.muli %bits, %bits : i2
      %limit = arith.constant 1 : i2
      %opaque = arith.cmpi ult, %square, %limit : i2
      cf.cond_br %opaque, ^irrelevant, ^decide
    ^irrelevant:
      %low = simulation.ref.extract %copy from 0 : !simulation.ref<!flags> -> !ref
      simulation.ref.store %one to %low : !bit, !ref
      cf.br ^decide
    ^decide:
      %enabled = simulation.ref.load %enable : !ref -> !bit
      %condition = simulation.logic.is_true %enabled : !bit
      %both = arith.andi %condition, %opaque : i1
      cf.cond_br %both, ^join, ^set
    ^set:
      simulation.ref.store %one to %y : !bit, !ref
      cf.br ^join
    ^join:
      %old = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      simulation.suspend.any %x, %flags, %enable, %index edges [0, 0, 0, 0] to ^body : !ref, !simulation.ref<!flags>, !ref, !simulation.ref<!simulation.logic<2>>
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %flags = simulation.context.storage %ctx[2] : !simulation.ref<!flags>
      %index = simulation.context.storage %ctx[5] : !simulation.ref<!simulation.logic<2>>
      %saved = simulation.context.storage %ctx[7] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %x : !bit, !ref
      %idx = simulation.ref.load %index : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %wide = simulation.logic.resize %idx signed = false : !simulation.logic<2> -> !simulation.logic<65>
      %selected = simulation.ref.array_element %flags[%wide] : (!simulation.ref<!flags>, !simulation.logic<65>) -> !ref
      %flag = simulation.ref.load %selected : !ref -> !bit
      %test = simulation.logic.is_true %flag : !bit
      cf.cond_br %test, ^set, ^join
    ^set:
      simulation.ref.store %one to %x : !bit, !ref
      cf.br ^join
    ^join:
      %old = simulation.ref.load %y : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      simulation.suspend.any %y, %flags, %index edges [0, 0, 0] to ^body : !ref, !simulation.ref<!flags>, !simulation.ref<!simulation.logic<2>>
    }
  }
}
