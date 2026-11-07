// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-fold-small-domains)))' | FileCheck %s

// IEEE 1800-2023 12.4.2/12.5.3: prove the actual binary match predicates
// disjoint without assuming a unique qualifier. Widths exceed exhaustive
// enumeration. A no-match branch requires its own proof and stays here.

// -----

module {
  simulation.design @masked_select_count {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "masked_select_count"
    // CHECK-LABEL: simulation.func @masked_select_count
    // CHECK-NOT: arith.constant 99
    // CHECK: arith.constant 77
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @masked_select_count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %low = arith.andi %x, %mask : i20
      %v0 = arith.constant 32 : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %n0 = arith.extui %p0 : i1 to i32
      %v1 = arith.constant 40 : i20
      %p1 = arith.cmpi eq, %low, %v1 : i20
      %inc1 = arith.addi %n0, %one : i32
      %n1 = arith.select %p1, %inc1, %n0 : i32
      %v2 = arith.constant 48 : i20
      %p2 = arith.cmpi eq, %low, %v2 : i20
      %inc2 = arith.addi %n1, %one : i32
      %n2 = arith.select %p2, %inc2, %n1 : i32
      %v3 = arith.constant 56 : i20
      %p3 = arith.cmpi eq, %low, %v3 : i20
      %inc3 = arith.addi %n2, %one : i32
      %n3 = arith.select %p3, %inc3, %n2 : i32
      %v4 = arith.constant 0 : i20
      %p4 = arith.cmpi eq, %x, %v4 : i20
      %inc4 = arith.addi %n3, %one : i32
      %n4 = arith.select %p4, %inc4, %n3 : i32
      %v5 = arith.constant 8 : i20
      %p5 = arith.cmpi eq, %x, %v5 : i20
      %inc5 = arith.addi %n4, %one : i32
      %n5 = arith.select %p5, %inc5, %n4 : i32
      %v6 = arith.constant 16 : i20
      %p6 = arith.cmpi eq, %x, %v6 : i20
      %inc6 = arith.addi %n5, %one : i32
      %n6 = arith.select %p6, %inc6, %n5 : i32
      %v7 = arith.constant 24 : i20
      %p7 = arith.cmpi eq, %x, %v7 : i20
      %inc7 = arith.addi %n6, %one : i32
      %count = arith.select %p7, %inc7, %n6 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
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

module {
  simulation.design @masked_add_count {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "masked_add_count"
    // CHECK-LABEL: simulation.func @masked_add_count
    // CHECK-NOT: arith.constant 99
    // CHECK: arith.constant 77
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @masked_add_count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
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

module {
  simulation.design @masked_upper_bound {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "masked_upper_bound"
    // CHECK-LABEL: simulation.func @masked_upper_bound
    // CHECK-NOT: arith.constant 99
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @masked_upper_bound(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %multi = arith.cmpi ule, %count, %one : i32
      cf.cond_br %multi, ^done, ^report
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @overlapping_masks {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "overlapping_masks"
    // CHECK-LABEL: simulation.func @overlapping_masks
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @overlapping_masks(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask0 = arith.constant 63 : i20
      %mask1 = arith.constant 16 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low0 = arith.andi %x, %mask0 : i20
      %low1 = arith.andi %x, %mask1 : i20
      %p0 = arith.cmpi eq, %low0, %v0 : i20
      %p1 = arith.cmpi eq, %low1, %v1 : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @shared_count_occurrences {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "shared_count_occurrences"
    // CHECK-LABEL: simulation.func @shared_count_occurrences
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @shared_count_occurrences(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %shared = arith.addi %e0, %e1 : i32
      %count = arith.addi %shared, %shared : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @nonzero_base {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "nonzero_base"
    // CHECK-LABEL: simulation.func @nonzero_base
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @nonzero_base(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %one : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @signed_boolean_is_not_a_match_count {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "signed_boolean_is_not_a_match_count"
    // CHECK-LABEL: simulation.func @signed_boolean_is_not_a_match_count
    // CHECK: %[[MULTI:.*]] = arith.cmpi ule
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @signed_boolean_is_not_a_match_count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extsi %p0 : i1 to i32
      %e1 = arith.extsi %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %multi = arith.cmpi ule, %count, %one : i32
      cf.cond_br %multi, ^done, ^report
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @mismatched_select_predecessor {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "mismatched_select_predecessor"
    // CHECK-LABEL: simulation.func @mismatched_select_predecessor
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @mismatched_select_predecessor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %two = arith.constant 2 : i32
      %inc = arith.addi %e0, %one : i32
      %count = arith.select %p1, %inc, %two : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @independent_boolean {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "independent_boolean"
    // CHECK-LABEL: simulation.func @independent_boolean
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @independent_boolean(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}, %p: i1 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 63 : i20
      %v0 = arith.constant 32 : i20
      %v1 = arith.constant 0 : i20
      %low = arith.andi %mask, %x : i20
      %p0 = arith.cmpi eq, %low, %v0 : i20
      %p1 = arith.cmpi eq, %v1, %x : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %flag = arith.extui %p : i1 to i32
      %count = arith.addi %e0, %flag : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @distinct_load_snapshots {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i20 design
    simulation.code_unit.decl 1 in 0 function hierarchy "distinct_load_snapshots"
    // CHECK-LABEL: simulation.func @distinct_load_snapshots
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @distinct_load_snapshots(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i20>
      %before = simulation.ref.load %ref : !simulation.ref<i20> -> i20
      %p0 = arith.cmpi eq, %before, %v1 : i20
      simulation.ref.store %zero to %ref : i20, !simulation.ref<i20>
      %after = simulation.ref.load %ref : !simulation.ref<i20> -> i20
      %p1 = arith.cmpi eq, %after, %zero : i20
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @wide_apint {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "wide_apint"
    // CHECK-LABEL: simulation.func @wide_apint
    // CHECK-NOT: arith.constant 99
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @wide_apint(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i130 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %mask = arith.constant 1267650600228229401496703205376 : i130
      %zero = arith.constant 0 : i130
      %low = arith.andi %x, %mask : i130
      %p0 = arith.cmpi eq, %low, %zero : i130
      %p1 = arith.cmpi eq, %low, %mask : i130
      %e0 = arith.extui %p0 : i1 to i32
      %e1 = arith.extui %p1 : i1 to i32
      %count = arith.addi %e0, %e1 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @signed_counter_bound {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "signed_counter_bound"
    // CHECK-LABEL: simulation.func @signed_counter_bound
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @signed_counter_bound(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i2 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i2
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %e0 = arith.extui %p0 : i1 to i2
      %e1 = arith.extui %p1 : i1 to i2
      %count = arith.addi %e0, %e1 : i2
      %multi = arith.cmpi sgt, %count, %one : i2
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant -1 : i2
      simulation.return %bad : i2
    ^done:
      simulation.return %count : i2
    }
  }
}
