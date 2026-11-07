// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{maximum-rounds=0 closed-model=true}))' -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --split-input-file --mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{maximum-rounds=0 closed-model=true}))' -o %t.serial
// RUN: diff %t %t.serial
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{maximum-rounds=0}))' | FileCheck %s --check-prefix=OPEN
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-fold-small-domains)))' | FileCheck %s --check-prefix=EXACT
// EXACT-LABEL: simulation.design @case_exact_x_z
// EXACT-NOT: arith.constant 99
// EXACT: arith.constant 77
// EXACT-LABEL: simulation.design @case_exact_known_x
// EXACT-NOT: arith.constant 99
// EXACT: arith.constant 77
// EXACT-LABEL: simulation.design @wide_case_exact
// EXACT-NOT: arith.constant 99
// EXACT: arith.constant 77
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off},talos-sim-forward-copy-processes{maximum-rounds=0 closed-model=true},talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=FROZEN
// FROZEN-LABEL: simulation.design @default_x
// FROZEN: simulation.func @check(
// FROZEN: arith.constant 99
// OPEN-LABEL: simulation.design @default_x
// OPEN: arith.constant 99

// IEEE 1800-2023 6.8/11.4/12.5.1/12.5.3: X is not a wildcard in
// casez. Prove never-Z from the default and every writer, without assuming
// binary values or reset. Keep no-match checks, casex, possible Z writers,
// duplicate/overlapping labels and independent SSA snapshots conservative.
// CHECK-LABEL: simulation.design @default_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @default_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @explicit_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @explicit_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @explicit_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @explicit_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @transient_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @transient_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %last = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %last to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @captured_net_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @captured_net_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @binary_normalizes_z
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @binary_normalizes_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %normalized = simulation.logic.binary or %v, %zero : !simulation.logic<4>
      simulation.ref.store %normalized to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @unary_plus
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @unary_plus {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %normalized = simulation.logic.unary plus %v : (!simulation.logic<4>) -> !simulation.logic<4>
      simulation.ref.store %normalized to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @unary_bit_not
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @unary_bit_not {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %normalized = simulation.logic.unary bit_not %v : (!simulation.logic<4>) -> !simulation.logic<4>
      simulation.ref.store %normalized to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @unary_negate
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @unary_negate {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %normalized = simulation.logic.unary negate %v : (!simulation.logic<4>) -> !simulation.logic<4>
      simulation.ref.store %normalized to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @shift_preserves_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @shift_preserves_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %zero = arith.constant 0 : i32
      %shifted = simulation.logic.shift left %v by %zero : (!simulation.logic<4>, i32) -> !simulation.logic<4>
      simulation.ref.store %shifted to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @resize_preserves_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @resize_preserves_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %c0 = simulation.logic.constant 0 : i8, 0 : i8 : !simulation.logic<8>
      %c1 = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<8>, !simulation.logic<8>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<8>, !simulation.logic<8>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %v = simulation.net.read %n : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %resized = simulation.logic.resize %v signed = false : !simulation.logic<4> -> !simulation.logic<8>
      simulation.ref.store %resized to %r : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @delayed_z_payload
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @delayed_z_payload {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 5
      simulation.nba.enqueue %v to %r after %delay : (!simulation.logic<4>, !simulation.ref<!simulation.logic<4>>, !simulation.time) -> ()
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @foreign_value
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @foreign_value {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %foreign: !simulation.logic<4> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      simulation.ref.store %foreign to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @external_setter
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @external_setter {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design {observability = 2 : i32}
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @top_input
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @top_input {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.port.decl 0 in 0 source 0 net = false at 0 : !simulation.logic<4> input ordinal 0 hierarchy "input"
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @cycle_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @cycle_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.ref.load %other : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
    simulation.code_unit.decl 3 in 0 function hierarchy "back"
    simulation.func @back(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %other : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @cycle_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @cycle_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.ref.load %other : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
    simulation.code_unit.decl 3 in 0 function hierarchy "back"
    simulation.func @back(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %other : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @partial_x_hold
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @partial_x_hold {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %whole = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %x = simulation.logic.extract %whole from 0 : !simulation.logic<4> -> !simulation.logic<2>
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !simulation.logic<2>
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %low = simulation.ref.extract %r from 0 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<2>>
      %v = simulation.logic.constant 0 : i2, 3 : i2 : !simulation.logic<2>
      simulation.ref.store %v to %low : !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @partial_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @partial_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %whole = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %x = simulation.logic.extract %whole from 0 : !simulation.logic<4> -> !simulation.logic<2>
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !simulation.logic<2>
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %low = simulation.ref.extract %r from 0 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<2>>
      %v = simulation.logic.constant 3 : i2, 3 : i2 : !simulation.logic<2>
      simulation.ref.store %v to %low : !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @rhs_wildcards_disjoint
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @rhs_wildcards_disjoint {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<2> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<2>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %c0 = simulation.logic.constant 2 : i2, 2 : i2 : !simulation.logic<2>
      %c1 = simulation.logic.constant 3 : i2, 2 : i2 : !simulation.logic<2>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @rhs_wildcards_overlap
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @rhs_wildcards_overlap {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<2> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<2>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %c0 = simulation.logic.constant 2 : i2, 2 : i2 : !simulation.logic<2>
      %c1 = simulation.logic.constant 1 : i2, 1 : i2 : !simulation.logic<2>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<2>, !simulation.logic<2>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @casex_keeps_x
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @casex_keeps_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casexz_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casexz_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @duplicate_labels
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @duplicate_labels {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @distinct_snapshots
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @distinct_snapshots {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %y = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %p1 = simulation.logic.compare casez_eq %y, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @case_exact_x_z
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @case_exact_x_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare case_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare case_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @case_exact_known_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @case_exact_known_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare case_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare case_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @wide_case_exact
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @wide_case_exact {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<130> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<130>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<130>> -> !simulation.logic<130>
      %c0 = simulation.logic.constant 0 : i130, 1361129467683753853853498429727072845823 : i130 : !simulation.logic<130>
      %c1 = simulation.logic.constant 680564733841876926926749214863536422912 : i130, 1361129467683753853853498429727072845823 : i130 : !simulation.logic<130>
      %p0 = simulation.logic.compare case_eq %x, %c0 : (!simulation.logic<130>, !simulation.logic<130>) -> i1
      %p1 = simulation.logic.compare case_eq %x, %c1 : (!simulation.logic<130>, !simulation.logic<130>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @packed_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @packed_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.packed_array<3 : 0 x !simulation.logic<1>> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.packed_array<3 : 0 x !simulation.logic<1>>>
      %whole = simulation.ref.load %r : !simulation.ref<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.packed_array<3 : 0 x !simulation.logic<1>>
      %x = simulation.packed.flatten %whole : (!simulation.packed_array<3 : 0 x !simulation.logic<1>>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @member_default_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @member_default_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>>
      %whole = simulation.ref.load %r : !simulation.ref<!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>> -> !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %x = simulation.aggregate.extract %whole[0] : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @aggregate_default_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @aggregate_default_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %whole = simulation.aggregate.default : !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %x = simulation.aggregate.extract %whole[0] : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @invalid_array_default_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @invalid_array_default_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %known = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %element = simulation.aggregate.construct %known : (!simulation.logic<4>) -> !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %array = simulation.aggregate.construct %element : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.unpacked_array<0 : 0 x !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>>
      %index = arith.constant 9 : i32
      %selected = simulation.array.extract_dynamic %array[%index] : (!simulation.unpacked_array<0 : 0 x !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>>, i32) -> !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %x = simulation.aggregate.extract %selected[0] : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [0 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @member_default_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @member_default_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>>
      %whole = simulation.ref.load %r : !simulation.ref<!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>> -> !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %x = simulation.aggregate.extract %whole[0] : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @aggregate_default_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @aggregate_default_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %whole = simulation.aggregate.default : !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %x = simulation.aggregate.extract %whole[0] : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @invalid_array_default_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @invalid_array_default_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %known = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %element = simulation.aggregate.construct %known : (!simulation.logic<4>) -> !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %array = simulation.aggregate.construct %element : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.unpacked_array<0 : 0 x !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>>
      %index = arith.constant 9 : i32
      %selected = simulation.array.extract_dynamic %array[%index] : (!simulation.unpacked_array<0 : 0 x !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>>, i32) -> !simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>
      %x = simulation.aggregate.extract %selected[0] : (!simulation.unpacked_struct<[#simulation.field<name = "v", type = !simulation.logic<4>, ordinal = 0, packedOffset = 0, initializer = #simulation.frozen_constant<value = [15 : i4, 15 : i4], isSigned = false> : !simulation.logic<4>>]>) -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @ref_copy_x
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @ref_copy_x {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %other : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.ref.copy %other to %r : !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @ref_copy_z
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @ref_copy_z {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %other : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.ref.copy %other to %r : !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @mux_x_arm
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @mux_x_arm {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %enable: !simulation.logic<1> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      %drive = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %selected = simulation.logic.mux %enable ? %drive : %v : (!simulation.logic<1>, !simulation.logic<4>, !simulation.logic<4>) -> !simulation.logic<4>
      simulation.ref.store %selected to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @tristate_z_arm
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @tristate_z_arm {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %enable: !simulation.logic<1> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      %drive = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %selected = simulation.logic.mux %enable ? %drive : %v : (!simulation.logic<1>, !simulation.logic<4>, !simulation.logic<4>) -> !simulation.logic<4>
      simulation.ref.store %selected to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @phi_x_known_arms
// CHECK: simulation.func @check(
// CHECK-NOT: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @phi_x_known_arms {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %known = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %v = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      cf.cond_br %choose, ^first, ^second
    ^first:
      cf.br ^join(%known : !simulation.logic<4>)
    ^second:
      cf.br ^join(%v : !simulation.logic<4>)
    ^join(%joined: !simulation.logic<4>):
      simulation.ref.store %joined to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @phi_z_arm
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @phi_z_arm {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %known = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %v = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      cf.cond_br %choose, ^first, ^second
    ^first:
      cf.br ^join(%known : !simulation.logic<4>)
    ^second:
      cf.br ^join(%v : !simulation.logic<4>)
    ^join(%joined: !simulation.logic<4>):
      simulation.ref.store %joined to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// CHECK-LABEL: simulation.design @loop_carried_phi
// CHECK: simulation.func @check(
// CHECK: arith.constant 99
// CHECK: arith.constant 77
// CHECK: simulation.return
module {
  simulation.design @loop_carried_phi {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c0 = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %c1 = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %p0 = simulation.logic.compare casez_eq %x, %c0 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %p1 = simulation.logic.compare casez_eq %x, %c1 : (!simulation.logic<4>, !simulation.logic<4>) -> i1
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %one = arith.constant 1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^bad, ^done
    ^bad:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      %zero = arith.constant 0 : i32
      %none = arith.cmpi eq, %count, %zero : i32
      cf.cond_br %none, ^missing, ^matched
    ^missing:
      %missing = arith.constant 77 : i32
      simulation.return %missing : i32
    ^matched:
      simulation.return %count : i32
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "write"
    simulation.func @write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      cf.br ^loop(%v : !simulation.logic<4>)
    ^loop(%joined: !simulation.logic<4>):
      simulation.ref.store %joined to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.cond_br %choose, ^done, ^loop(%joined : !simulation.logic<4>)
    ^done:
      simulation.return
    }
  }
}
