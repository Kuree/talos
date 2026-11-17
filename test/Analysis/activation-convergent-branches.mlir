// RUN: talos-opt %s --test-talos-activation-canonicalize -o /dev/null 2>&1 | FileCheck %s

// An exhausted case statement whose every arm ends in the same block, through
// empty forwarding blocks, is no test at all. Here each arm has two case
// items, and the blocks interleave as lowered from source. Folding one link
// makes the previous link foldable, but the greedy driver does not revisit
// that branch, so it needs about one round per link and gives up after its
// iteration limit. Activation canonicalization collapses the chain in one
// post-order sweep.
// CHECK-LABEL: canonicalize @exhausted_case converged=1
// CHECK-NEXT: func.func @exhausted_case
// CHECK-NEXT: %[[NONE:.+]] = arith.constant 86 : i8
// CHECK-NEXT: return %[[NONE]]
func.func @exhausted_case(%op: i8) -> i8 {
  %k0 = arith.constant 60 : i8
  %k1 = arith.constant 61 : i8
  %k2 = arith.constant 62 : i8
  %k3 = arith.constant 63 : i8
  %k4 = arith.constant 64 : i8
  %k5 = arith.constant 65 : i8
  %k6 = arith.constant 66 : i8
  %k7 = arith.constant 67 : i8
  %k8 = arith.constant 68 : i8
  %k9 = arith.constant 69 : i8
  %k10 = arith.constant 70 : i8
  %k11 = arith.constant 71 : i8
  %k12 = arith.constant 72 : i8
  %k13 = arith.constant 73 : i8
  %k14 = arith.constant 74 : i8
  %k15 = arith.constant 75 : i8
  %k16 = arith.constant 76 : i8
  %k17 = arith.constant 77 : i8
  %k18 = arith.constant 78 : i8
  %k19 = arith.constant 79 : i8
  %none = arith.constant 86 : i8
  %c0 = arith.cmpi eq, %op, %k0 : i8
  cf.cond_br %c0, ^arm0, ^second0
^arm0:
  cf.br ^join
^first1:
  %f1 = arith.cmpi eq, %op, %k2 : i8
  cf.cond_br %f1, ^arm1, ^second1
^second0:
  %s0 = arith.cmpi eq, %op, %k1 : i8
  cf.cond_br %s0, ^arm0, ^first1
^arm1:
  cf.br ^join
^first2:
  %f2 = arith.cmpi eq, %op, %k4 : i8
  cf.cond_br %f2, ^arm2, ^second2
^second1:
  %s1 = arith.cmpi eq, %op, %k3 : i8
  cf.cond_br %s1, ^arm1, ^first2
^arm2:
  cf.br ^join
^first3:
  %f3 = arith.cmpi eq, %op, %k6 : i8
  cf.cond_br %f3, ^arm3, ^second3
^second2:
  %s2 = arith.cmpi eq, %op, %k5 : i8
  cf.cond_br %s2, ^arm2, ^first3
^arm3:
  cf.br ^join
^first4:
  %f4 = arith.cmpi eq, %op, %k8 : i8
  cf.cond_br %f4, ^arm4, ^second4
^second3:
  %s3 = arith.cmpi eq, %op, %k7 : i8
  cf.cond_br %s3, ^arm3, ^first4
^arm4:
  cf.br ^join
^first5:
  %f5 = arith.cmpi eq, %op, %k10 : i8
  cf.cond_br %f5, ^arm5, ^second5
^second4:
  %s4 = arith.cmpi eq, %op, %k9 : i8
  cf.cond_br %s4, ^arm4, ^first5
^arm5:
  cf.br ^join
^first6:
  %f6 = arith.cmpi eq, %op, %k12 : i8
  cf.cond_br %f6, ^arm6, ^second6
^second5:
  %s5 = arith.cmpi eq, %op, %k11 : i8
  cf.cond_br %s5, ^arm5, ^first6
^arm6:
  cf.br ^join
^first7:
  %f7 = arith.cmpi eq, %op, %k14 : i8
  cf.cond_br %f7, ^arm7, ^second7
^second6:
  %s6 = arith.cmpi eq, %op, %k13 : i8
  cf.cond_br %s6, ^arm6, ^first7
^arm7:
  cf.br ^join
^first8:
  %f8 = arith.cmpi eq, %op, %k16 : i8
  cf.cond_br %f8, ^arm8, ^second8
^second7:
  %s7 = arith.cmpi eq, %op, %k15 : i8
  cf.cond_br %s7, ^arm7, ^first8
^arm8:
  cf.br ^join
^first9:
  %f9 = arith.cmpi eq, %op, %k18 : i8
  cf.cond_br %f9, ^arm9, ^second9
^second8:
  %s8 = arith.cmpi eq, %op, %k17 : i8
  cf.cond_br %s8, ^arm8, ^first9
^arm9:
  cf.br ^join
^second9:
  %s9 = arith.cmpi eq, %op, %k19 : i8
  cf.cond_br %s9, ^arm9, ^default
^default:
  cf.br ^join
^join:
  return %none : i8
}

// A switch whose every case forwards the same value collapses too.
// CHECK-LABEL: canonicalize @uniform_switch converged=1
// CHECK-NEXT: func.func @uniform_switch(%[[FLAG:.+]]: i32, %[[V:.+]]: i8)
// CHECK-NEXT: return %[[V]]
func.func @uniform_switch(%flag: i32, %v: i8) -> i8 {
  cf.switch %flag : i32, [
    default: ^a,
    0: ^b,
    1: ^a
  ]
^a:
  cf.br ^join(%v : i8)
^b:
  cf.br ^join(%v : i8)
^join(%r: i8):
  return %r : i8
}

// The dead test reaches its operands along two paths; each is erased once.
// CHECK-LABEL: canonicalize @diamond_test converged=1
// CHECK-NEXT: func.func @diamond_test
// CHECK-NEXT: return
func.func @diamond_test(%op: i8) {
  %x = arith.extui %op : i8 to i16
  %one = arith.constant 1 : i16
  %y = arith.addi %x, %one : i16
  %c = arith.cmpi ult, %x, %y : i16
  cf.cond_br %c, ^a, ^b
^a:
  cf.br ^join
^b:
  cf.br ^join
^join:
  return
}

// One arm forwards a different value, so its test stays (as a select).
// CHECK-LABEL: canonicalize @distinct_arm converged=1
// CHECK: %[[TEST:.+]] = arith.cmpi eq
// CHECK: arith.select %[[TEST]]
func.func @distinct_arm(%op: i8) -> i8 {
  %k = arith.constant 60 : i8
  %a = arith.constant 1 : i8
  %b = arith.constant 2 : i8
  %c = arith.cmpi eq, %op, %k : i8
  cf.cond_br %c, ^arm, ^other
^arm:
  cf.br ^join(%a : i8)
^other:
  cf.br ^join(%b : i8)
^join(%v: i8):
  return %v : i8
}
