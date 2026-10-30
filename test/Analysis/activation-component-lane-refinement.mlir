// RUN: talos-opt %s --test-talos-activation-regions='functions=a,b,sel,mux components=true reaching-values=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=EXTRACT
// RUN: talos-opt %s --test-talos-activation-regions='functions=a,b,copy,reader,writer components=true reaching-values=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=COPY
// RUN: talos-opt %s --test-talos-activation-regions='components=true reaching-values=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=ALL

// The genuine a <-> b cycle is encountered first. It must not stop refinement
// of either independent false cycle: a whole-load/extract dependency, or an
// identity publication that needs three windows. Only a <-> b remains cyclic.
// EXTRACT: slice components: valid nodes=4 components=3 cyclic=1 events=4
// COPY: slice components: valid nodes=7 components=6 cyclic=1 events=5
// ALL: slice components: valid nodes=9 components=8 cyclic=1 events=7
module {
  simulation.design @mixed_cycles {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : !simulation.logic<3> design
    simulation.storage.decl 3 in 0 : !simulation.logic<1> design
    simulation.storage.decl 4 in 0 : !simulation.logic<2> design
    simulation.storage.decl 5 in 0 : !simulation.logic<4> design
    simulation.storage.decl 6 in 0 : !simulation.logic<4> design
    simulation.storage.decl 7 in 0 : !simulation.logic<1> design
    simulation.storage.decl 8 in 0 : !simulation.logic<1> design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "sel"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "mux"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "copy"
    simulation.code_unit.decl 6 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "writer"
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %b = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %b : !simulation.ref<i8> -> i8
      simulation.ref.store %v to %a : i8, !simulation.ref<i8>
      simulation.suspend.change %b to ^body : !simulation.ref<i8>
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %b = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %a : !simulation.ref<i8> -> i8
      simulation.ref.store %v to %b : i8, !simulation.ref<i8>
      simulation.suspend.change %a to ^body : !simulation.ref<i8>
    }
    simulation.func @sel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %way = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<3>>
      %sel = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %w = simulation.ref.load %way : !simulation.ref<!simulation.logic<3>> -> !simulation.logic<3>
      %bit = simulation.logic.extract %w from 2 : !simulation.logic<3> -> !simulation.logic<1>
      simulation.ref.store %bit to %sel : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.change %way to ^body : !simulation.ref<!simulation.logic<3>>
    }
    simulation.func @mux(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %way = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<3>>
      %sel = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<1>>
      %lru = simulation.context.storage %ctx[4] : !simulation.ref<!simulation.logic<2>>
      %out = simulation.ref.extract %way from 1 : !simulation.ref<!simulation.logic<3>> -> !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %l = simulation.ref.load %lru : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %i = simulation.logic.resize %s signed = false : !simulation.logic<1> -> !simulation.logic<2>
      %picked = simulation.logic.dyn_extract %l from %i : (!simulation.logic<2>, !simulation.logic<2>) -> !simulation.logic<1>
      simulation.ref.store %picked to %out : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.any %sel, %lru edges [0, 0] to ^body : !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.logic<2>>
    }
    simulation.func @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      %in = simulation.context.storage %ctx[5] : !simulation.ref<!simulation.logic<4>>
      %out = simulation.context.storage %ctx[6] : !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
      %out = simulation.context.storage %ctx[6] : !simulation.ref<!simulation.logic<4>>
      %flag = simulation.context.storage %ctx[7] : !simulation.ref<!simulation.logic<1>>
      %mode = simulation.context.storage %ctx[8] : !simulation.ref<!simulation.logic<1>>
      %bit0 = simulation.ref.extract %out from 0 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %b = simulation.ref.load %bit0 : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %m = simulation.ref.load %mode : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %f = simulation.logic.binary and %b, %m : !simulation.logic<1>
      simulation.ref.store %f to %flag : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.any %bit0, %mode edges [0, 0] to ^body : !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.logic<1>>
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %in = simulation.context.storage %ctx[5] : !simulation.ref<!simulation.logic<4>>
      %flag = simulation.context.storage %ctx[7] : !simulation.ref<!simulation.logic<1>>
      %bit3 = simulation.ref.extract %in from 3 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %f = simulation.ref.load %flag : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      simulation.ref.store %f to %bit3 : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.change %flag to ^body : !simulation.ref<!simulation.logic<1>>
    }
  }
}
