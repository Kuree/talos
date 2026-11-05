// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-fold-small-domains)))' | FileCheck %s

// IEEE 1800-2023 12.5.3, 12.4.2: a unique case over a 3-bit two-state
// expression whose items cover every value without overlap can neither match
// twice nor match nothing, so the report branch and the empty default go.

module {
  simulation.design @exhaustive {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "decode"
    // CHECK-LABEL: simulation.func @decode
    // CHECK-NOT: cf.cond_br
    // CHECK-NOT: arith.constant 99
    // CHECK-NOT: arith.constant 77
    // CHECK: return
    simulation.func @decode(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i3 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %c0 = arith.constant 0 : i3
      %c2 = arith.constant 2 : i3
      %c4 = arith.constant 4 : i3
      %c6 = arith.constant 6 : i3
      %z = arith.constant 0 : i8
      %one = arith.constant 1 : i8
      %x6 = arith.andi %x, %c6 : i3
      %x4 = arith.andi %x, %c4 : i3
      %m0 = arith.cmpi eq, %x6, %c0 : i3
      %m1 = arith.cmpi eq, %x6, %c2 : i3
      %m2 = arith.cmpi eq, %x4, %c4 : i3
      %e0 = arith.extui %m0 : i1 to i8
      %e1 = arith.extui %m1 : i1 to i8
      %e2 = arith.extui %m2 : i1 to i8
      %s01 = arith.addi %e0, %e1 : i8
      %count = arith.addi %s01, %e2 : i8
      %multi = arith.cmpi ugt, %count, %one : i8
      cf.cond_br %multi, ^report, ^match
    ^report:
      %r = arith.constant 99 : i8
      simulation.return %r : i8
    ^match:
      %none = arith.cmpi eq, %count, %z : i8
      cf.cond_br %none, ^default, ^item
    ^default:
      %d = arith.constant 77 : i8
      simulation.return %d : i8
    ^item:
      simulation.return %count : i8
    }
  }
}

// -----

// Items 1 and 2 overlap for x = 6: the multiple-match report stays.

module {
  simulation.design @overlap {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "decode"
    // CHECK-LABEL: simulation.func @decode
    // CHECK: %[[MULTI:.*]] = arith.cmpi ugt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @decode(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i3 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %c0 = arith.constant 0 : i3
      %c2 = arith.constant 2 : i3
      %c6 = arith.constant 6 : i3
      %one = arith.constant 1 : i8
      %x6 = arith.andi %x, %c6 : i3
      %x2 = arith.andi %x, %c2 : i3
      %m0 = arith.cmpi eq, %x6, %c0 : i3
      %m1 = arith.cmpi eq, %x2, %c2 : i3
      %m2 = arith.cmpi eq, %x6, %c6 : i3
      %e0 = arith.extui %m0 : i1 to i8
      %e1 = arith.extui %m1 : i1 to i8
      %e2 = arith.extui %m2 : i1 to i8
      %s01 = arith.addi %e0, %e1 : i8
      %count = arith.addi %s01, %e2 : i8
      %multi = arith.cmpi ugt, %count, %one : i8
      cf.cond_br %multi, ^report, ^done
    ^report:
      %r = arith.constant 99 : i8
      simulation.return %r : i8
    ^done:
      simulation.return %count : i8
    }
  }
}

// -----

// A dispatch chain on the first-match index: once the index is neither 0 nor
// 1, the dominating branch edges leave only 2, so the final else (the empty
// default) is unreachable.

module {
  simulation.design @chain {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "dispatch"
    // CHECK-LABEL: simulation.func @dispatch
    // CHECK-NOT: arith.constant 77
    // CHECK: arith.constant 30
    // CHECK-NOT: arith.constant 77
    simulation.func @dispatch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i2 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %k0 = arith.constant 0 : i2
      %k1 = arith.constant 1 : i2
      %i0 = arith.constant 0 : i8
      %i1 = arith.constant 1 : i8
      %i2 = arith.constant 2 : i8
      %m0 = arith.cmpi eq, %x, %k0 : i2
      %m1 = arith.cmpi eq, %x, %k1 : i2
      %rest = arith.select %m1, %i1, %i2 : i8
      %index = arith.select %m0, %i0, %rest : i8
      %is0 = arith.cmpi eq, %index, %i0 : i8
      cf.cond_br %is0, ^a, ^not0
    ^a:
      %ra = arith.constant 10 : i8
      simulation.return %ra : i8
    ^not0:
      %is1 = arith.cmpi eq, %index, %i1 : i8
      cf.cond_br %is1, ^b, ^not1
    ^b:
      %rb = arith.constant 20 : i8
      simulation.return %rb : i8
    ^not1:
      %is2 = arith.cmpi eq, %index, %i2 : i8
      cf.cond_br %is2, ^c, ^default
    ^c:
      %rc = arith.constant 30 : i8
      simulation.return %rc : i8
    ^default:
      %rd = arith.constant 77 : i8
      simulation.return %rd : i8
    }
  }
}

// -----

// Two views of one packed value: element [0] of `bit [1:0] s` is s[1], the
// high bit of the flattened image. `s == 0`, `s == 1` and `s[1]` are then
// exhaustive and disjoint, and the report folds. A view taken as independent
// bits could not be decided.

module {
  simulation.design @views {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "views"
    // CHECK-LABEL: simulation.func @views
    // CHECK-NOT: arith.constant 99
    simulation.func @views(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %s: !simulation.packed_array<1 : 0 x i1> {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %k0 = arith.constant 0 : i2
      %k1 = arith.constant 1 : i2
      %one = arith.constant 1 : i8
      %flat = simulation.packed.flatten %s : (!simulation.packed_array<1 : 0 x i1>) -> i2
      %high = simulation.aggregate.extract %s[0] : (!simulation.packed_array<1 : 0 x i1>) -> i1
      %m0 = arith.cmpi eq, %flat, %k0 : i2
      %m1 = arith.cmpi eq, %flat, %k1 : i2
      %e0 = arith.extui %m0 : i1 to i8
      %e1 = arith.extui %m1 : i1 to i8
      %e2 = arith.extui %high : i1 to i8
      %s01 = arith.addi %e0, %e1 : i8
      %count = arith.addi %s01, %e2 : i8
      %multi = arith.cmpi ugt, %count, %one : i8
      cf.cond_br %multi, ^report, ^done
    ^report:
      %r = arith.constant 99 : i8
      simulation.return %r : i8
    ^done:
      simulation.return %count : i8
    }
  }
}

// -----

// More than 16 input bits: not evaluated, although `x % 4` takes one of four
// values whatever x is.

module {
  simulation.design @wide {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "wide"
    // CHECK-LABEL: simulation.func @wide
    // CHECK: cf.cond_br %{{[0-9]+}}, ^bb1, ^bb2
    simulation.func @wide(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i17 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %k0 = arith.constant 0 : i17
      %k1 = arith.constant 1 : i17
      %k2 = arith.constant 2 : i17
      %k3 = arith.constant 3 : i17
      %low = arith.andi %x, %k3 : i17
      %m0 = arith.cmpi eq, %low, %k0 : i17
      %m1 = arith.cmpi eq, %low, %k1 : i17
      %m2 = arith.cmpi eq, %low, %k2 : i17
      %m3 = arith.cmpi eq, %low, %k3 : i17
      %a01 = arith.ori %m0, %m1 : i1
      %a23 = arith.ori %m2, %m3 : i1
      %any = arith.ori %a01, %a23 : i1
      cf.cond_br %any, ^a, ^b
    ^a:
      %ra = arith.constant 1 : i8
      simulation.return %ra : i8
    ^b:
      %rb = arith.constant 2 : i8
      simulation.return %rb : i8
    }
  }
}

// -----

// Match flags computed by four-state operations are independent leaves: a z
// in a casez expression can make two items match (12.5.1), and the report
// must stay (12.4.2.1).

!bit = !simulation.logic<1>
module {
  simulation.design @four_state {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "flags"
    // CHECK-LABEL: simulation.func @flags
    // CHECK: %[[MULTI:.*]] = arith.cmpi ugt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @flags(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !bit {simulation.capture_kind = 1 : i32}, %b: !bit {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i8
      %ta = simulation.logic.is_true %a : !bit
      %tb = simulation.logic.is_true %b : !bit
      %ea = arith.extui %ta : i1 to i8
      %eb = arith.extui %tb : i1 to i8
      %count = arith.addi %ea, %eb : i8
      %multi = arith.cmpi ugt, %count, %one : i8
      cf.cond_br %multi, ^report, ^done
    ^report:
      %r = arith.constant 99 : i8
      simulation.return %r : i8
    ^done:
      simulation.return %count : i8
    }
  }
}

// -----

// A select whose condition the dominating edge decides.

module {
  simulation.design @select {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "pick"
    // CHECK-LABEL: simulation.func @pick
    // CHECK: ^bb1:
    // CHECK-NOT: arith.select
    // CHECK: simulation.return %{{.*}} : i8
    simulation.func @pick(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i1 {simulation.capture_kind = 1 : i32}, %p: i8 {simulation.capture_kind = 1 : i32}, %q: i8 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      cf.cond_br %x, ^set, ^clear
    ^set:
      %v = arith.select %x, %p, %q : i8
      simulation.return %v : i8
    ^clear:
      simulation.return %q : i8
    }
  }
}

// -----

// A loop-carried leaf: the exit edge leaves i != 3 inside the body, where
// i + 1 cannot wrap to 0.

module {
  simulation.design @loop {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "count"
    // CHECK-LABEL: simulation.func @count
    // CHECK-NOT: arith.constant 99
    simulation.func @count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %c0 = arith.constant 0 : i2
      %c1 = arith.constant 1 : i2
      %c3 = arith.constant 3 : i2
      cf.br ^head(%c0 : i2)
    ^head(%i: i2):
      %done = arith.cmpi eq, %i, %c3 : i2
      cf.cond_br %done, ^exit, ^body
    ^body:
      %next = arith.addi %i, %c1 : i2
      %wrap = arith.cmpi eq, %next, %c0 : i2
      cf.cond_br %wrap, ^bad, ^head(%next : i2)
    ^bad:
      %r = arith.constant 99 : i8
      simulation.return %r : i8
    ^exit:
      %e = arith.constant 1 : i8
      simulation.return %e : i8
    }
  }
}

// -----

// No constraint from a join of both edges, nor from a branch whose two
// edges enter the same block.

module {
  simulation.design @joins {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "join"
    simulation.code_unit.decl 2 in 0 function hierarchy "same"
    // CHECK-LABEL: simulation.func @join
    // CHECK: ^bb3:
    // CHECK-NEXT: cf.cond_br %arg1
    simulation.func @join(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i1 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      cf.cond_br %x, ^a, ^b
    ^a:
      cf.br ^join
    ^b:
      cf.br ^join
    ^join:
      cf.cond_br %x, ^t, ^f
    ^t:
      %rt = arith.constant 1 : i8
      simulation.return %rt : i8
    ^f:
      %rf = arith.constant 2 : i8
      simulation.return %rf : i8
    }
    // CHECK-LABEL: simulation.func @same
    // CHECK: ^bb1:
    // CHECK-NEXT: cf.cond_br %arg1
    simulation.func @same(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i1 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      cf.cond_br %x, ^d, ^d
    ^d:
      cf.cond_br %x, ^t, ^f
    ^t:
      %rt = arith.constant 1 : i8
      simulation.return %rt : i8
    ^f:
      %rf = arith.constant 2 : i8
      simulation.return %rf : i8
    }
  }
}

// -----

// Results that may be poison are not interpreted: a shift by at least the
// width, and an add with no-signed-wrap, which overflows at x = 3.

module {
  simulation.design @poison {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "shift"
    simulation.code_unit.decl 2 in 0 function hierarchy "nsw"
    // CHECK-LABEL: simulation.func @shift
    // CHECK: cf.cond_br
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i2 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i2
      %zero = arith.constant 0 : i2
      %s = arith.shli %one, %x : i2
      %c = arith.cmpi ne, %s, %zero : i2
      cf.cond_br %c, ^t, ^f
    ^t:
      %rt = arith.constant 1 : i8
      simulation.return %rt : i8
    ^f:
      %rf = arith.constant 2 : i8
      simulation.return %rf : i8
    }
    // CHECK-LABEL: simulation.func @nsw
    // CHECK: ^bb1:
    // CHECK: cf.cond_br
    simulation.func @nsw(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i3 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %one = arith.constant 1 : i3
      %seven = arith.constant 7 : i3
      %zero = arith.constant 0 : i3
      %last = arith.cmpi eq, %x, %seven : i3
      cf.cond_br %last, ^skip, ^go
    ^go:
      %a = arith.addi %x, %one overflow<nsw> : i3
      %wrap = arith.cmpi eq, %a, %zero : i3
      cf.cond_br %wrap, ^t, ^f
    ^t:
      %rt = arith.constant 1 : i8
      simulation.return %rt : i8
    ^f:
      %rf = arith.constant 2 : i8
      simulation.return %rf : i8
    ^skip:
      %rs = arith.constant 3 : i8
      simulation.return %rs : i8
    }
  }
}

// -----

// A packed struct field sits at its packedOffset in the flattened image: the
// first field `hi` is bits [3:2] of `{hi, lo}`.

!pair = !simulation.packed_struct<[#simulation.field<name = "hi", type = i2, ordinal = 0, packedOffset = 2>, #simulation.field<name = "lo", type = i2, ordinal = 1, packedOffset = 0>]>
module {
  simulation.design @fields {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "fields"
    // CHECK-LABEL: simulation.func @fields
    // CHECK-NOT: arith.constant 99
    simulation.func @fields(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %v: !pair {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %two = arith.constant 2 : i4
      %flat = simulation.packed.flatten %v : (!pair) -> i4
      %hi = simulation.aggregate.extract %v[0] : (!pair) -> i2
      %shifted = arith.shrui %flat, %two : i4
      %top = arith.trunci %shifted : i4 to i2
      %differ = arith.cmpi ne, %hi, %top : i2
      cf.cond_br %differ, ^bad, ^ok
    ^bad:
      %r = arith.constant 99 : i8
      simulation.return %r : i8
    ^ok:
      %o = arith.constant 1 : i8
      simulation.return %o : i8
    }
  }
}
