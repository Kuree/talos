// RUN: talos-opt %s --split-input-file --verify-diagnostics

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @cancel_negative {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls, schedule.prime_on_spawn} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{cancel indices must name distinct existing snapshot targets}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] {cancel_indices = array<i32: -1>} : !o, i1, !o, !r
      simulation.suspend.forever to ^parked
    ^parked:
      simulation.return
    }
    simulation.func private @primary(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }
    simulation.func private @sample(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 3 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }
  }
}


// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @cancel_large {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls, schedule.prime_on_spawn} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{cancel indices must name distinct existing snapshot targets}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] {cancel_indices = array<i32: 1>} : !o, i1, !o, !r
      simulation.suspend.forever to ^parked
    ^parked:
      simulation.return
    }
    simulation.func private @primary(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }
    simulation.func private @sample(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 3 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }
  }
}


// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @cancel_duplicate {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls, schedule.prime_on_spawn} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{cancel indices must name distinct existing snapshot targets}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] {cancel_indices = array<i32: 0, 0>} : !o, i1, !o, !r
      simulation.suspend.forever to ^parked
    ^parked:
      simulation.return
    }
    simulation.func private @primary(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }
    simulation.func private @sample(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 3 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }
  }
}
