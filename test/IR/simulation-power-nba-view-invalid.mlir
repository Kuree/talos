// RUN: talos-opt %s --split-input-file --verify-diagnostics
// IEEE 1801-2018 9.5.3 / IEEE 1800-2023 11.5.1: raw guarded windows
// require integral persistent roots, whole epochs and a pure capture-free guard.

!c = !simulation.context
!v = i8
!r = !simulation.ref<!simulation.string>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @string {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.string design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires a packed value and fixed-width integral storage root}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<!simulation.process>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @process {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.process design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires a packed value and fixed-width integral storage root}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<f64>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @real {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : f64 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires a packed value and fixed-width integral storage root}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.string>>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @nested_managed {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.unpacked_array<0 : 1 x !simulation.string> design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires a packed value and fixed-width integral storage root}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<!simulation.logic<16>>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @four_state_root {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<16> design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{value and root must use the same state domain}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = !simulation.logic<8>
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @four_state_value {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = simulation.logic.constant 1 : i8, 0 : i8 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{value and root must use the same state domain}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @automatic_root {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 automatic
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @projected_root {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %view = simulation.ref.extract %root from 0 : !r -> !simulation.ref<i8>
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue_view %ctx, %value in %view window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !simulation.ref<i8>, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @projected_epoch {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i128 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %wide_epoch = simulation.context.storage %ctx[2] : !simulation.ref<i128>
      %projected = simulation.ref.extract %wide_epoch from 1 : !simulation.ref<i128> -> !e
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%projected, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @automatic_epoch {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i64 automatic
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %automatic = simulation.context.storage %ctx[2] : !e
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%automatic, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @captured_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 1 : !o
      // expected-error @+1 {{guard must be a capture-free i1 observer binding}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}, %captured: !r {simulation.capture_kind = 1 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!v = i8
!r = !simulation.ref<i16>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @writing_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i16 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %root = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %zero = arith.constant 0 : i64
      %end = arith.constant 8 : i64
      %valid = arith.constant true
      %value = arith.constant 1 : !v
      %guard = simulation.observer.bind @guard values (%root : !r) captures 0 : !o
      // expected-error @+1 {{guard evaluator must be read-only}}
      simulation.power.nba.enqueue_view %ctx, %value in %root window (%zero, %end) at %zero when %valid guard %guard epochs (%epoch, %zero, %epoch, %zero) : (!c, !v, !r, i64, i64, i64, i1, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      %state = simulation.context.storage %ctx[0] : !r
      %data = arith.constant 0 : i16
      simulation.ref.store %data to %state : i16, !r
      simulation.return %one : i1
    }
  }
}
