// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// A branch that directly follows the schedule.known.roots test it branches on
// lowers with the test: the cached, backed-off and refreshed answers each take
// their edge straight to the successor they select, carrying the branch's
// converted successor operands (here both planes of a logic value). The
// runtime's answer keeps the branch's weights, here none.

// CHECK-LABEL: llvm.func @step(
// CHECK: %[[SUMMARY:.*]] = llvm.mlir.addressof @__talos_state_unknown_summary_v1
// CHECK: %[[CLEAN:.*]] = llvm.icmp "eq"
// CHECK-NEXT: llvm.cond_br %[[CLEAN]] weights([1048575, 1]), ^[[COPY:bb[0-9]+]](%[[V:.*]], %[[U:.*]] : i8, i8), ^[[REFRESH:bb[0-9]+]]
// CHECK: ^[[REFRESH]]:
// CHECK: llvm.cond_br %{{.*}} weights([1048575, 1]), ^[[WAIT:bb[0-9]+]], ^[[CALL:bb[0-9]+]]
// CHECK: ^[[WAIT]]:
// CHECK: llvm.br ^[[BODY:bb[0-9]+]](%[[V]], %[[U]] : i8, i8)
// CHECK: ^[[CALL]]:
// CHECK: %[[R:.*]] = llvm.call @talos_rt_v1_native_state_refresh_unknown_summary(
// CHECK: %[[OK:.*]] = llvm.icmp "ne" %[[R]]
// CHECK-NEXT: llvm.cond_br %[[OK]], ^[[COPY]](%[[V]], %[[U]] : i8, i8), ^[[BODY]](%[[V]], %[[U]] : i8, i8)
// CHECK: ^[[COPY]](%{{.*}}: i8, %{{.*}}: i8):
// CHECK: ^[[BODY]](%{{.*}}: i8, %{{.*}}: i8):

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !l8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %c = simulation.ref.load %a : !r8 -> !l8
      %known = schedule.known.roots %a, %b : !r8, !r8
      cf.cond_br %known, ^copy(%c : !l8), ^body(%c : !l8)
    ^copy(%x: !l8):
      simulation.ref.store %x to %out : !l8, !r8
      simulation.return
    ^body(%y: !l8):
      %d = simulation.ref.load %b : !r8 -> !l8
      %e = simulation.logic.binary add %d, %y : !l8
      simulation.ref.store %e to %out : !l8, !r8
      simulation.return
    }
  }
}

// -----

// A test of a part of a root has no summary bit and never holds; the branch
// keeps both edges on the constant answer, so neither successor is left
// without a predecessor before region simplification.

// CHECK-LABEL: llvm.func @step(
// CHECK-NOT: unknown_summary
// CHECK: %[[NEVER:.*]] = llvm.mlir.constant(false) : i1
// CHECK-NEXT: llvm.cond_br %[[NEVER]], ^[[COPY:bb[0-9]+]], ^[[BODY:bb[0-9]+]]
// CHECK: ^[[COPY]]:
// CHECK: ^[[BODY]]:

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !l8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %c = simulation.ref.load %a : !r8 -> !l8
      %bit = simulation.ref.extract %a from 2 : !r8 -> !simulation.ref<!l1>
      %known = schedule.known.roots %bit : !simulation.ref<!l1>
      cf.cond_br %known, ^copy, ^body
    ^copy:
      simulation.ref.store %c to %out : !l8, !r8
      simulation.return
    ^body:
      %d = simulation.ref.load %b : !r8 -> !l8
      simulation.ref.store %d to %out : !l8, !r8
      simulation.return
    }
  }
}

// -----

// A test used as a value merges its answers in one block argument. Here the
// first test feeds a successor operand of the branch on the second, which
// lowers as branches carrying the merged answer on every edge.

// CHECK-LABEL: llvm.func @step(
// CHECK: %[[TRUE:.*]] = llvm.mlir.constant(true) : i1
// CHECK-NEXT: llvm.cond_br %{{.*}} weights([1048575, 1]), ^[[MERGE:bb[0-9]+]](%[[TRUE]] : i1), ^
// CHECK: %[[FALSE:.*]] = llvm.mlir.constant(false) : i1
// CHECK-NEXT: llvm.br ^[[MERGE]](%[[FALSE]] : i1)
// CHECK: %[[ANSWER:.*]] = llvm.icmp "ne"
// CHECK-NEXT: llvm.br ^[[MERGE]](%[[ANSWER]] : i1)
// CHECK: ^[[MERGE]](%[[FIRST:.*]]: i1):
// CHECK: llvm.cond_br %{{.*}} weights([1048575, 1]), ^[[COPY:bb[0-9]+]](%[[FIRST]] : i1), ^
// CHECK: llvm.br ^[[BODY:bb[0-9]+]]{{$}}
// CHECK: llvm.cond_br %{{.*}}, ^[[COPY]](%[[FIRST]] : i1), ^[[BODY]]{{$}}

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !l8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %first = schedule.known.roots %a : !r8
      %second = schedule.known.roots %b : !r8
      cf.cond_br %second, ^copy(%first : i1), ^body
    ^copy(%k: i1):
      %v = simulation.logic.from_bits %k : i1 -> !l1
      %w = simulation.logic.resize %v signed = false : !l1 -> !l8
      simulation.ref.store %w to %out : !l8, !r8
      simulation.return
    ^body:
      %c = simulation.ref.load %a : !r8 -> !l8
      simulation.ref.store %c to %out : !l8, !r8
      simulation.return
    }
  }
}

// -----

// A test of two-state roots only always holds: they cannot hold x or z (IEEE
// 1800-2023 6.11.2). The branch keeps both edges on the constant answer.

// CHECK-LABEL: llvm.func @step(
// CHECK-NOT: unknown_summary
// CHECK: %[[ALWAYS:.*]] = llvm.mlir.constant(true) : i1
// CHECK-NEXT: llvm.cond_br %[[ALWAYS]], ^{{bb[0-9]+}}, ^{{bb[0-9]+}}

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : i8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %c = simulation.ref.load %a : !r8 -> !l8
      %two = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %known = schedule.known.roots %two : !simulation.ref<i8>
      cf.cond_br %known, ^copy, ^body
    ^copy:
      simulation.ref.store %c to %out : !l8, !r8
      simulation.return
    ^body:
      simulation.return
    }
  }
}

// -----

// Both answers may reach one block with different operands: every edge
// carries its own operands, here both planes of the selected logic value.

// CHECK-LABEL: llvm.func @step(
// CHECK: llvm.cond_br %{{.*}} weights([1048575, 1]), ^[[JOIN:bb[0-9]+]](%[[CV:.*]], %[[CU:.*]] : i8, i8), ^
// CHECK: llvm.br ^[[JOIN]](%[[DV:.*]], %[[DU:.*]] : i8, i8)
// CHECK: llvm.cond_br %{{.*}}, ^[[JOIN]](%[[CV]], %[[CU]] : i8, i8), ^[[JOIN]](%[[DV]], %[[DU]] : i8, i8)

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !l8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %c = simulation.ref.load %a : !r8 -> !l8
      %d = simulation.ref.load %b : !r8 -> !l8
      %known = schedule.known.roots %a, %b : !r8, !r8
      cf.cond_br %known, ^join(%c : !l8), ^join(%d : !l8)
    ^join(%x: !l8):
      simulation.ref.store %x to %out : !l8, !r8
      simulation.return
    }
  }
}

// -----

// Only a branch right after its test lowers with it; with an operation in
// between the test merges its answers, which then select the successor.

// CHECK-LABEL: llvm.func @step(
// CHECK: llvm.cond_br %{{.*}} weights([1048575, 1]), ^[[MERGE:bb[0-9]+]](%{{.*}} : i1), ^
// CHECK: ^[[MERGE]](%[[KNOWN:.*]]: i1):
// CHECK: llvm.cond_br %[[KNOWN]], ^

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !l8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %known = schedule.known.roots %a : !r8
      %c = simulation.ref.load %b : !r8 -> !l8
      cf.cond_br %known, ^copy, ^body
    ^copy:
      simulation.ref.store %c to %out : !l8, !r8
      simulation.return
    ^body:
      simulation.return
    }
  }
}

// -----

// A two-state build tracks no unknown summary: the test never holds and the
// original body runs.

// CHECK-LABEL: llvm.func @step(
// CHECK-NOT: unknown_summary
// CHECK: %[[NEVER:.*]] = llvm.mlir.constant(false) : i1
// CHECK-NEXT: llvm.cond_br %[[NEVER]], ^{{bb[0-9]+}}, ^{{bb[0-9]+}}

!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {
  native.two_state,
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @kr {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !l8 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !l8 design hierarchy "top.b"
    simulation.storage.decl 2 in 0 : !l8 design hierarchy "top.out"
    simulation.func @__talos_root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %process = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      simulation.call @step(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @step(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %c = simulation.ref.load %a : !r8 -> !l8
      %known = schedule.known.roots %a : !r8
      cf.cond_br %known, ^copy, ^body
    ^copy:
      simulation.ref.store %c to %out : !l8, !r8
      simulation.return
    ^body:
      simulation.return
    }
  }
}
