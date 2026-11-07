// RUN: talos-opt %s --test-talos-activation-regions='idempotence=true reaching-values=true' -o %t.after 2>&1 | FileCheck %s
// RUN: talos-opt %s -o %t.before
// RUN: diff %t.before %t.after

// Fixed-input idempotence treats resolved net reads like validated storage
// reads. It preserves exact X/Z values and implicit held cells. Net writes
// remain unsupported, and the selected handle's incoming-state dependency
// must not disappear when a store subsequently resets that selector.
!word = !simulation.logic<8>
!ref = !simulation.ref<!word>
!net = !simulation.net<!word>
module {
  simulation.design @net_idempotence {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !word design
    simulation.storage.decl 1 in 0 : !word design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : !word design
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.net.decl 1 in 0 : !word design
    simulation.net.decl 2 in 0 : !simulation.logic<16> design
    simulation.driver.decl 0 in 0 drives 1 : !word design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "implicit_hold"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "explicit_hold"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "old_snapshot"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "state_selector"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "net_write"

    // CHECK-LABEL: regions @implicit_hold valid=1
    // CHECK-NEXT: idempotent=1
    simulation.func @implicit_hold(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %enable = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<1>>
      %input = simulation.context.net %ctx[1] : !net
      %output = simulation.context.storage %ctx[0] : !ref
      cf.br ^body
    ^body:
      %control = simulation.net.read %enable : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
      %flag = simulation.logic.is_true %control : !simulation.logic<1>
      cf.cond_br %flag, ^write, ^wait
    ^write:
      %value = simulation.net.read %input : !net -> !word
      simulation.ref.store %value to %output : !word, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %enable, %input edges [0, 0] to ^body : !simulation.net<!simulation.logic<1>>, !net
    }

    // CHECK-LABEL: regions @explicit_hold valid=1
    // CHECK-NEXT: idempotent=1
    simulation.func @explicit_hold(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %enable = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<1>>
      %input = simulation.context.net %ctx[1] : !net
      %output = simulation.context.storage %ctx[0] : !ref
      cf.br ^body
    ^body:
      %old = simulation.ref.load %output : !ref -> !word
      %control = simulation.net.read %enable : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
      %flag = simulation.logic.is_true %control : !simulation.logic<1>
      cf.cond_br %flag, ^write, ^hold
    ^write:
      %incoming = simulation.net.read %input : !net -> !word
      cf.br ^publish(%incoming : !word)
    ^hold:
      cf.br ^publish(%old : !word)
    ^publish(%value: !word):
      simulation.ref.store %value to %output : !word, !ref
      simulation.suspend.any %enable, %input edges [0, 0] to ^body : !simulation.net<!simulation.logic<1>>, !net
    }

    // CHECK-LABEL: regions @old_snapshot valid=1
    // CHECK-NEXT: idempotent=0
    simulation.func @old_snapshot(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.net %ctx[1] : !net
      %state = simulation.context.storage %ctx[0] : !ref
      %output = simulation.context.storage %ctx[1] : !ref
      cf.br ^body
    ^body:
      %old = simulation.ref.load %state : !ref -> !word
      %value = simulation.net.read %input : !net -> !word
      simulation.ref.store %value to %state : !word, !ref
      simulation.ref.store %old to %output : !word, !ref
      simulation.suspend.change %input to ^body : !net
    }

    // CHECK-LABEL: regions @state_selector valid=1
    // CHECK-NEXT: idempotent=0
    simulation.func @state_selector(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.net %ctx[2] : !simulation.net<!simulation.logic<16>>
      %low = simulation.net.extract %input from 0 : !simulation.net<!simulation.logic<16>> -> !net
      %high = simulation.net.extract %input from 8 : !simulation.net<!simulation.logic<16>> -> !net
      %selector = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %output = simulation.context.storage %ctx[3] : !ref
      %false = arith.constant false
      cf.br ^body
    ^body:
      %old = simulation.ref.load %selector : !simulation.ref<i1> -> i1
      %selected = arith.select %old, %high, %low : !net
      %value = simulation.net.read %selected : !net -> !word
      simulation.ref.store %false to %selector : i1, !simulation.ref<i1>
      simulation.ref.store %value to %output : !word, !ref
      simulation.suspend.change %input to ^body : !simulation.net<!simulation.logic<16>>
    }

    // CHECK-LABEL: regions @net_write valid=1
    // CHECK-NEXT: idempotent=0
    simulation.func @net_write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      %input = simulation.context.storage %ctx[0] : !ref
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!word>
      %net = simulation.context.net %ctx[1] : !net
      %output = simulation.context.storage %ctx[1] : !ref
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !ref -> !word
      simulation.driver.drive %driver = %value : !simulation.driver<!word>, !word
      %resolved = simulation.net.read %net : !net -> !word
      simulation.ref.store %resolved to %output : !word, !ref
      simulation.suspend.change %input to ^body : !ref
    }
  }
}
