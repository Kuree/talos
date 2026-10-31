// RUN: talos-opt %s --split-input-file --verify-diagnostics
// IEEE 1801-2018 6.50: retained callbacks need stable explicit roots, pure
// sampling and qualified mask scope. Reject malformed inventories and aliases.

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @negative_count {
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
      // expected-error @+1 {{target count must name a valid trailing operand span}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets -1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @oversized_count {
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
      // expected-error @+1 {{target count must name a valid trailing operand span}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 99 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @negative_conditions {
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
      // expected-error @+1 {{condition count must be nonnegative}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions -1 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @invalid_edge {
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
      // expected-error @+1 {{contains an invalid event edge}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [99] indices [-1] : !o, i1, !o, !r
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
  simulation.design @initial_type {
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
      // expected-error @+1 {{initial value #0 does not match}}
      simulation.event.snapshot.register %ctx values [%primary, %target, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, !r, !o, !r
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
  simulation.design @payload_width {
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
      %wide = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{sampler must be a dependency-free packed observer matching the target payload width}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %wide] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !simulation.ref<i8>
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
  simulation.design @duplicate_alias {
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
      %alias = simulation.context.storage %ctx[0] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{targets may overlap through a storage alias}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target, %alias] targets 2 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r, !r
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
  simulation.design @local_target {
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
      %local = simulation.ref.alloc %initial : i1 -> !r
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{targets must be whole persistent storage roots}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %local] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @projected_target {
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
      %wide = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %slice = simulation.ref.extract %wide from 0 : !simulation.ref<i8> -> !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{targets must be whole persistent storage roots}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %slice] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @automatic_target {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 automatic
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
      // expected-error @+1 {{snapshot roots must have persistent declaration lifetime}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @local_capture {
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
      %local = simulation.ref.alloc %initial : i1 -> !r
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%local : !r) captures 1 : !o
      // expected-error @+1 {{callback captures and dependencies must be whole persistent packed storage or nets}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @automatic_net {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.net.decl 0 in 0 : i1 automatic
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls, schedule.prime_on_spawn} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %net = simulation.context.net %ctx[0] : !simulation.net<i1>
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%net : !simulation.net<i1>) captures 1 : !o
      // expected-error @+1 {{snapshot roots must have persistent declaration lifetime}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
        %source: !simulation.net<i1> {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 3 : i64} {
      %value = simulation.net.read %source : !simulation.net<i1> -> i1
      simulation.return %value : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @nonprimed_owner {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{requires one entry registration in a private detached primed persistent fork}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
  simulation.design @owner_does_not_park {
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
      // expected-error @+1 {{owner must park forever immediately after registration}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
      %extra = arith.constant 9 : i32
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
  simulation.design @public_callback {
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
      // expected-error @+1 {{callbacks must name defined private observers}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
    simulation.func @sample(%ctx: !c {simulation.capture_kind = 0 : i32},
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
  simulation.design @unbound_read {
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
      // expected-error @+1 {{callback closure must only read bound state}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
      %unbound = simulation.context.storage %ctx[1] : !r
      %value = simulation.ref.load %unbound : !r -> i1
      simulation.return %value : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @transitive_write {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.write"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls, schedule.prime_on_spawn} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      // expected-error @+1 {{callback closure must only read bound state}}
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
    simulation.func private @write(%ctx: !c {simulation.capture_kind = 0 : i32}, %source: !r {simulation.capture_kind = 1 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %value = simulation.ref.load %source : !r -> i1
      simulation.ref.store %value to %source : i1, !r
      simulation.return %value : i1
    }
    simulation.func private @sample(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 3 : i64} {
      %value = simulation.call @write(%ctx, %source) : (!c, !r) -> i1
      simulation.return %value : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @mask_primary_sampler {
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
      // expected-error @+1 {{snapshot mask evaluator must bind only a snapshot sampler}}
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      simulation.event.snapshot.register %ctx values [%sample, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
      %mask = simulation.event.snapshot.mask %ctx
      %value = arith.trunci %mask : i64 to i1
      simulation.return %value : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @mask_iff_sampler {
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
      // expected-error @+1 {{snapshot mask evaluator must bind only a snapshot sampler}}
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %sample, %target] targets 1 conditions 1 edges [1] indices [0] : !o, i1, !o, !o, !r
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
      %mask = simulation.event.snapshot.mask %ctx
      %value = arith.trunci %mask : i64 to i1
      simulation.return %value : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!o = !simulation.observer<i1>
module {
  simulation.design @mask_direct_call {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 fork hierarchy "top.owner"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.primary"
    simulation.code_unit.decl 3 in 0 observer hierarchy "top.sample"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.direct"
    simulation.func private @owner(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64, internal, schedule.detached_controls, schedule.prime_on_spawn} {
      %target = simulation.context.storage %ctx[0] : !r
      %source = simulation.context.storage %ctx[1] : !r
      %initial = arith.constant false
      %primary = simulation.observer.bind @primary values (%source, %source : !r, !r) captures 1 : !o
      %sample = simulation.observer.bind @sample values (%source : !r) captures 1 : !o
      simulation.event.snapshot.register %ctx values [%primary, %initial, %sample, %target] targets 1 conditions 0 edges [1] indices [-1] : !o, i1, !o, !r
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
    simulation.func @direct(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %source = simulation.context.storage %ctx[1] : !r
      // expected-error @+1 {{snapshot mask evaluators may only run as snapshot samplers}}
      %result = simulation.call @sample(%ctx, %source) : (!c, !r) -> i1
      simulation.return %result : i1
    }
    simulation.func private @sample(%ctx: !c {simulation.capture_kind = 0 : i32},
        %source: !r {simulation.capture_kind = 2 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 3 : i64} {
      %mask = simulation.event.snapshot.mask %ctx
      %value = arith.trunci %mask : i64 to i1
      simulation.return %value : i1
    }
  }
}
