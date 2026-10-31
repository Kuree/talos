// RUN: talos-opt --split-input-file --verify-diagnostics %s
// IEEE 1801-2018 9.7.3: commit guards must be pure, fully defined and
// capture-free; complete static registers retain their bounds and lifetime.

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      %byte = arith.constant 1 : i8
      // expected-error @+1 {{requires matching packed value, backing, and output types}}
      simulation.power.nba.enqueue %ctx, %byte to %q, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i8, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      %bad = simulation.context.storage %ctx[3] : !simulation.ref<i32>
      // expected-error @+1 {{requires i64 epoch references}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %guard epochs (%bad, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !simulation.ref<i32>, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      %wide = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %slice = simulation.ref.extract %wide from 0 : !simulation.ref<i8> -> !r
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue %ctx, %one to %slice, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      %automatic = simulation.ref.alloc %one : i1 -> !r
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue %ctx, %one to %automatic, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      %indirect = arith.select %one, %guard, %guard : !o
      // expected-error @+1 {{guard must be a capture-free i1 observer binding}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %indirect epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 1 : !o
      // expected-error @+1 {{guard must be a capture-free i1 observer binding}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}, %value: !r {simulation.capture_kind = 1 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !simulation.observer<i8>
      // expected-error @+1 {{guard must be a capture-free i1 observer binding}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !simulation.observer<i8>, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i8
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant 1 : i8
      simulation.return %one : i8
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      // expected-error @+1 {{guard evaluator must be read-only}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      %q = simulation.context.storage %ctx[0] : !r
      simulation.ref.store %one to %q : i1, !r
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      // expected-error @+1 {{guard evaluator must name a defined simulation observer}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64}
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 automatic
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue %ctx, %one to %q, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      simulation.return
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}

// -----

!c = !simulation.context
!r = !simulation.ref<i1>
!e = !simulation.ref<i64>
!o = !simulation.observer<i1>
module {
  simulation.design @invalid_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i64 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.storage.decl 4 in 0 : i1 automatic
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.drive"
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.guard"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %epoch = simulation.context.storage %ctx[1] : !e
      %one = arith.constant true
      %z64 = arith.constant 0 : i64
      %guard = simulation.observer.bind @guard values (%q : !r) captures 0 : !o
      %a = simulation.context.storage %ctx[4] : !r
      cf.cond_br %one, ^static_path, ^automatic_path
    ^static_path:
      cf.br ^join(%q : !r)
    ^automatic_path:
      cf.br ^join(%a : !r)
    ^join(%target: !r):
      // expected-error @+1 {{requires whole design/static storage references}}
      simulation.power.nba.enqueue %ctx, %one to %target, %q guard %guard epochs (%epoch, %z64, %epoch, %z64) : (!c, i1, !r, !r, !o, !e, i64, !e, i64) -> ()
      cf.br ^join(%target : !r)
    }
    simulation.func private @guard(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant true
      simulation.return %one : i1
    }
  }
}
