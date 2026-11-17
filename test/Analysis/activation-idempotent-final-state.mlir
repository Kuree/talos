// RUN: talos-opt %s '--test-talos-activation-regions=idempotence=true reaching-values=true inputs=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -o %t.original
// RUN: diff %t.original %t.analyzed
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{explain=true}))' -o /dev/null 2>&1 | FileCheck %s --check-prefix=PLAN --implicit-check-not=owner=retained_scratch --implicit-check-not=owner=conditional_input --implicit-check-not=owner=dynamic_input

// A variable written in an always_comb is not in its implicit sensitivity
// (IEEE 1800-2023 9.2.2.2.1 b), and no other process may write it (9.2.2.2).
// When a loop writes it only on some iterations, its incoming value survives
// to the end of the activation. If that value only reaches its own final lane
// unchanged, then every written lane ends with either its incoming value or
// a value computed from unwritten inputs, chosen by unwritten inputs. A rerun
// with unchanged inputs therefore reproduces the final state, even though
// path enumeration cannot prove it through the loop. The incoming value must
// be an unchanged copy: a lane-aligned operation such as `~s` is not one.
!entries = !simulation.unpacked_array<0 : 1 x i8>
module {
  simulation.design @idempotent_final_state {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !entries design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.storage.decl 8 in 0 : i8 design
    simulation.storage.decl 9 in 0 : i8 design
    simulation.storage.decl 10 in 0 : i8 design
    simulation.storage.decl 11 in 0 : i8 design
    simulation.storage.decl 12 in 0 : i8 design
    simulation.storage.decl 13 in 0 : i8 design
    simulation.storage.decl 14 in 0 : i8 design
    simulation.storage.decl 15 in 0 : i8 design
    simulation.storage.decl 16 in 0 : !entries design
    simulation.storage.decl 17 in 0 : !entries design
    simulation.storage.decl 18 in 0 : !simulation.logic<8> design
    simulation.storage.decl 19 in 0 : i8 design

    // CHECK-LABEL: regions @retained_scratch valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=1
    // CHECK: final-input s0[0,16) s1[0,8) s2[0,8){{$}}
    // CHECK-NEXT: final-state-input s0[0,16) s1[0,8){{$}}
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "retained_scratch"
    simulation.func @retained_scratch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %out = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %zero = arith.constant 0 : i8
      %mask = arith.constant 15 : i8
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      simulation.ref.store %zero to %out : i8, !simulation.ref<i8>
      cf.br ^loop(%c0, %old : i32, i8)
    ^loop(%i: i32, %s: i8):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next(%s : i8)
    ^hit:
      %patched = arith.ori %entry, %mask : i8
      simulation.ref.store %patched to %out : i8, !simulation.ref<i8>
      cf.br ^next(%patched : i8)
    ^next(%t: i8):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, i8)
    ^done:
      simulation.ref.store %s to %scratch : i8, !simulation.ref<i8>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // The incoming value feeds an update of the same lane, so a rerun
    // accumulates again.
    // CHECK-LABEL: regions @accumulate valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s0[0,16) s1[0,8) s4[0,8){{$}}
    // PLAN-DAG: rejected: unwatched live-in on storage 4; owner=accumulate
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "accumulate"
    simulation.func @accumulate(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      %out = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %zero = arith.constant 0 : i8
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      simulation.ref.store %zero to %out : i8, !simulation.ref<i8>
      cf.br ^loop(%c0, %old : i32, i8)
    ^loop(%i: i32, %s: i8):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next(%s : i8)
    ^hit:
      %sum = arith.addi %s, %entry : i8
      simulation.ref.store %entry to %out : i8, !simulation.ref<i8>
      cf.br ^next(%sum : i8)
    ^next(%t: i8):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, i8)
    ^done:
      simulation.ref.store %s to %scratch : i8, !simulation.ref<i8>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // The incoming value decides whether the lane is replaced. That control
    // is a state input even though the retained value itself is unchanged.
    // CHECK-LABEL: regions @state_control valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s0[0,16) s6[0,8){{$}}
    // PLAN-DAG: rejected: unwatched live-in on storage 6; owner=state_control
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "state_control"
    simulation.func @state_control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %out = simulation.context.storage %ctx[7] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %zero = arith.constant 0 : i8
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      simulation.ref.store %zero to %out : i8, !simulation.ref<i8>
      cf.br ^loop(%c0, %old : i32, i8)
    ^loop(%i: i32, %s: i8):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %empty = arith.cmpi eq, %s, %zero : i8
      cf.cond_br %empty, ^hit, ^next(%s : i8)
    ^hit:
      simulation.ref.store %entry to %out : i8, !simulation.ref<i8>
      cf.br ^next(%entry : i8)
    ^next(%t: i8):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, i8)
    ^done:
      simulation.ref.store %s to %scratch : i8, !simulation.ref<i8>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // A lane-aligned bitwise update is not a copy: inverting the retained
    // value on an odd number of hits is undone by a rerun.
    // CHECK-LABEL: regions @invert valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s0[0,16) s1[0,8) s8[0,8){{$}}
    // PLAN-DAG: rejected: unwatched live-in on storage 8; owner=invert
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "invert"
    simulation.func @invert(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[8] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %ones = arith.constant -1 : i8
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      cf.br ^loop(%c0, %old : i32, i8)
    ^loop(%i: i32, %s: i8):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next(%s : i8)
    ^hit:
      %flipped = arith.xori %s, %ones : i8
      cf.br ^next(%flipped : i8)
    ^next(%t: i8):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, i8)
    ^done:
      simulation.ref.store %s to %scratch : i8, !simulation.ref<i8>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // A copy into other lanes of the same variable is not a self copy.
    // CHECK-LABEL: regions @shift_self valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s0[0,16) s1[0,8) s9[0,4){{$}}
    // PLAN-DAG: rejected: unwatched live-in on storage 9; owner=shift_self
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "shift_self"
    simulation.func @shift_self(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[9] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %four = arith.constant 4 : i8
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      cf.br ^loop(%c0, %old : i32, i8)
    ^loop(%i: i32, %s: i8):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next(%s : i8)
    ^hit:
      %moved = arith.shli %s, %four : i8
      cf.br ^next(%moved : i8)
    ^next(%t: i8):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, i8)
    ^done:
      simulation.ref.store %s to %scratch : i8, !simulation.ref<i8>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // The incoming value of one written variable copied into another.
    // CHECK-LABEL: regions @copy_other valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s1[0,8) s10[0,8){{$}}
    // PLAN-DAG: rejected: unwatched live-in on storage 10; owner=copy_other
    simulation.code_unit.decl 6 in 0 always_comb hierarchy "copy_other"
    simulation.func @copy_other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %x = simulation.context.storage %ctx[10] : !simulation.ref<i8>
      %y = simulation.context.storage %ctx[11] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %previous = simulation.ref.load %x : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      simulation.ref.store %k to %x : i8, !simulation.ref<i8>
      simulation.ref.store %previous to %y : i8, !simulation.ref<i8>
      simulation.suspend.any %key edges [0] to ^body : !simulation.ref<i8>
    }

    // Conditional stores, not promoted to SSA, decided by inputs only. The
    // variable is not written on every path (incomplete writes).
    // CHECK-LABEL: regions @conditional_input valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=1
    // CHECK: final-state-input s0[0,16) s1[0,8){{$}}
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "conditional_input"
    simulation.func @conditional_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[12] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      cf.br ^start
    ^start:
      cf.br ^loop(%c0 : i32)
    ^loop(%i: i32):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next
    ^hit:
      simulation.ref.store %entry to %scratch : i8, !simulation.ref<i8>
      cf.br ^next
    ^next:
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step : i32)
    ^done:
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // The same stores decided by the stored variable itself.
    // CHECK-LABEL: regions @conditional_state valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s0[0,16) s13[0,8){{$}}
    // PLAN-DAG: rejected: incomplete writes; owner=conditional_state
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "conditional_state"
    simulation.func @conditional_state(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %scratch = simulation.context.storage %ctx[13] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      %zero = arith.constant 0 : i8
      cf.br ^start
    ^start:
      cf.br ^loop(%c0 : i32)
    ^loop(%i: i32):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %current = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      %empty = arith.cmpi eq, %current, %zero : i8
      cf.cond_br %empty, ^hit, ^next
    ^hit:
      simulation.ref.store %entry to %scratch : i8, !simulation.ref<i8>
      cf.br ^next
    ^next:
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step : i32)
    ^done:
      simulation.suspend.any %entries edges [0] to ^start : !simulation.ref<!entries>
    }

    // A dynamic-index store selected by an input leaves every other element
    // with its incoming value.
    // CHECK-LABEL: regions @dynamic_input valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=1
    // CHECK: final-state-input s1[0,8){{$}}
    simulation.code_unit.decl 9 in 0 always_comb hierarchy "dynamic_input"
    simulation.func @dynamic_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 9 : i64} {
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %table = simulation.context.storage %ctx[16] : !simulation.ref<!entries>
      cf.br ^body
    ^body:
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %bit = arith.trunci %k : i8 to i1
      %index = arith.extui %bit : i1 to i32
      %slot = simulation.ref.array_element %table[%index] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      simulation.ref.store %k to %slot : i8, !simulation.ref<i8>
      simulation.suspend.any %key edges [0] to ^body : !simulation.ref<i8>
    }

    // The index comes from the stored array itself.
    // CHECK-LABEL: regions @dynamic_state valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s1[0,8) s17[0,1){{$}}
    // PLAN-DAG: rejected: incomplete writes; owner=dynamic_state
    simulation.code_unit.decl 10 in 0 always_comb hierarchy "dynamic_state"
    simulation.func @dynamic_state(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 10 : i64} {
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %table = simulation.context.storage %ctx[17] : !simulation.ref<!entries>
      %c0 = arith.constant 0 : i32
      cf.br ^body
    ^body:
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %first = simulation.ref.array_element %table[%c0] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %selector = simulation.ref.load %first : !simulation.ref<i8> -> i8
      %bit = arith.trunci %selector : i8 to i1
      %index = arith.extui %bit : i1 to i32
      %slot = simulation.ref.array_element %table[%index] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      simulation.ref.store %k to %slot : i8, !simulation.ref<i8>
      simulation.suspend.any %key edges [0] to ^body : !simulation.ref<i8>
    }

    // IEEE 1800-2023 6.11.2: a four-state value converted to two states and
    // back loses its X/Z bits, so the retained lane is not a copy.
    // CHECK-LABEL: regions @two_state_roundtrip valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // CHECK: final-state-input s0[0,16) s1[0,8) s18[0,8){{$}}
    // PLAN-DAG: rejected: unwatched live-in on storage 18; owner=two_state_roundtrip
    simulation.code_unit.decl 11 in 0 always_comb hierarchy "two_state_roundtrip"
    simulation.func @two_state_roundtrip(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 11 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[18] : !simulation.ref<!simulation.logic<8>>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      cf.br ^loop(%c0, %old : i32, !simulation.logic<8>)
    ^loop(%i: i32, %s: !simulation.logic<8>):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next(%s : !simulation.logic<8>)
    ^hit:
      %bits = simulation.logic.to_bits %s : !simulation.logic<8> -> i8
      %known = simulation.logic.from_bits %bits : i8 -> !simulation.logic<8>
      cf.br ^next(%known : !simulation.logic<8>)
    ^next(%t: !simulation.logic<8>):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, !simulation.logic<8>)
    ^done:
      simulation.ref.store %s to %scratch : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }

    // Bitwise operations are lane-aligned but never copies, even where a
    // rerun would be harmless: `s | a` is rejected conservatively.
    // CHECK-LABEL: regions @or_input valid=1
    // CHECK-NEXT: idempotent=0
    // CHECK-NEXT: final-state-idempotent=0
    // PLAN-DAG: rejected: unwatched live-in on storage 19; owner=or_input
    simulation.code_unit.decl 12 in 0 always_comb hierarchy "or_input"
    simulation.func @or_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 12 : i64} {
      %entries = simulation.context.storage %ctx[0] : !simulation.ref<!entries>
      %key = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[19] : !simulation.ref<i8>
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      %c2 = arith.constant 2 : i32
      cf.br ^start
    ^start:
      %old = simulation.ref.load %scratch : !simulation.ref<i8> -> i8
      cf.br ^loop(%c0, %old : i32, i8)
    ^loop(%i: i32, %s: i8):
      %more = arith.cmpi slt, %i, %c2 : i32
      cf.cond_br %more, ^body, ^done
    ^body:
      %slot = simulation.ref.array_element %entries[%i] : (!simulation.ref<!entries>, i32) -> !simulation.ref<i8>
      %entry = simulation.ref.load %slot : !simulation.ref<i8> -> i8
      %k = simulation.ref.load %key : !simulation.ref<i8> -> i8
      %hit = arith.cmpi eq, %entry, %k : i8
      cf.cond_br %hit, ^hit, ^next(%s : i8)
    ^hit:
      %merged = arith.ori %s, %entry : i8
      cf.br ^next(%merged : i8)
    ^next(%t: i8):
      %step = arith.addi %i, %c1 : i32
      cf.br ^loop(%step, %t : i32, i8)
    ^done:
      simulation.ref.store %s to %scratch : i8, !simulation.ref<i8>
      simulation.suspend.any %entries, %key edges [0, 0] to ^start : !simulation.ref<!entries>, !simulation.ref<i8>
    }
  }
}
