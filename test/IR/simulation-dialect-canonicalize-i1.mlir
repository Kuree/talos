// RUN: talos-opt %s --canonicalize="test-convergence=true" --cse -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %t --canonicalize="test-convergence=true" --cse -o %t.twice
// RUN: diff %t %t.twice

// Parsing a simulation type loads the dialect, whose canonicalizer registers
// these i1 arith identities (upstream arith leaves them).
func.func private @load_simulation_dialect(!simulation.logic<1>)

// i1 arith identities registered on the simulation dialect (upstream arith
// leaves them). A select with a constant, repeated or negated-condition arm
// is logic; short-circuit lowering produces these forms.
// CHECK-LABEL: func.func @i1_selects(
// CHECK-SAME: %[[C:.*]]: i1, %[[X:.*]]: i1)
// CHECK-DAG: %[[OR:.*]] = arith.ori %[[C]], %[[X]] : i1
// CHECK-DAG: %[[AND:.*]] = arith.andi %[[C]], %[[X]] : i1
// CHECK-DAG: %[[NOT:.*]] = arith.xori %[[C]], %{{.*}} : i1
// CHECK-DAG: %[[ANDN:.*]] = arith.andi %[[NOT]], %[[X]] : i1
// CHECK-DAG: %[[ORN:.*]] = arith.ori %[[NOT]], %[[X]] : i1
// CHECK-NOT: arith.select
// CHECK: return %[[OR]], %[[AND]], %[[ANDN]], %[[ORN]], %[[OR]], %[[AND]], %[[C]], %[[C]], %[[ANDN]], %[[ORN]]
func.func @i1_selects(%c: i1, %x: i1) -> (i1, i1, i1, i1, i1, i1, i1, i1, i1, i1) {
  %true = arith.constant true
  %false = arith.constant false
  %nc = arith.xori %c, %true : i1
  %0 = arith.select %c, %true, %x : i1
  %1 = arith.select %c, %x, %false : i1
  %2 = arith.select %c, %false, %x : i1
  %3 = arith.select %c, %x, %true : i1
  %4 = arith.select %c, %c, %x : i1
  %5 = arith.select %c, %x, %c : i1
  %6 = arith.select %c, %true, %c : i1
  %7 = arith.select %c, %c, %false : i1
  %8 = arith.select %c, %nc, %x : i1
  %9 = arith.select %c, %x, %nc : i1
  return %0, %1, %2, %3, %4, %5, %6, %7, %8, %9 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
}

// An i1 compared with a constant is a constant, the bit or its negation for
// every predicate; signed i1 values are 0 and -1.
// CHECK-LABEL: func.func @i1_compare_constant(
// CHECK-SAME: %[[X:.*]]: i1)
// CHECK-DAG: %[[TRUE:.*]] = arith.constant true
// CHECK-DAG: %[[FALSE:.*]] = arith.constant false
// CHECK-NOT: arith.cmpi
// CHECK-DAG: %[[NOT:.*]] = arith.xori %[[X]], %[[TRUE]] : i1
// CHECK: return %[[NOT]], %[[NOT]], %[[X]], %[[X]], %[[NOT]], %[[X]], %[[X]], %[[NOT]], %[[X]], %[[NOT]], %[[FALSE]], %[[TRUE]] :
func.func @i1_compare_constant(%x: i1) -> (i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1) {
  %true = arith.constant true
  %false = arith.constant false
  %0 = arith.cmpi eq, %x, %false : i1
  %1 = arith.cmpi ne, %x, %true : i1
  %2 = arith.cmpi ne, %x, %false : i1
  %3 = arith.cmpi eq, %x, %true : i1
  %4 = arith.cmpi ult, %x, %true : i1
  %5 = arith.cmpi ugt, %x, %false : i1
  %6 = arith.cmpi uge, %x, %true : i1
  %7 = arith.cmpi ule, %x, %false : i1
  %8 = arith.cmpi slt, %x, %false : i1
  %9 = arith.cmpi sgt, %x, %true : i1
  %10 = arith.cmpi ugt, %x, %true : i1
  %11 = arith.cmpi ule, %x, %true : i1
  return %0, %1, %2, %3, %4, %5, %6, %7, %8, %9, %10, %11 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
}

// Two i1 operands compare as logic; signed i1 values are 0 and -1.
// CHECK-LABEL: func.func @i1_compare_pair(
// CHECK-SAME: %[[A:.*]]: i1, %[[B:.*]]: i1)
// CHECK-DAG: %[[TRUE:.*]] = arith.constant true
// CHECK-DAG: %[[XOR:.*]] = arith.xori %[[A]], %[[B]] : i1
// CHECK-DAG: %[[XNOR:.*]] = arith.xori %[[XOR]], %[[TRUE]] : i1
// CHECK-DAG: %[[NOTA:.*]] = arith.xori %[[A]], %[[TRUE]] : i1
// CHECK-DAG: %[[NOTB:.*]] = arith.xori %[[B]], %[[TRUE]] : i1
// CHECK-DAG: %[[NA_AND_B:.*]] = arith.andi %[[NOTA]], %[[B]] : i1
// CHECK-DAG: %[[NA_OR_B:.*]] = arith.ori %[[NOTA]], %[[B]] : i1
// CHECK-DAG: %[[A_AND_NB:.*]] = arith.andi %[[A]], %[[NOTB]] : i1
// CHECK-DAG: %[[A_OR_NB:.*]] = arith.ori %[[A]], %[[NOTB]] : i1
// CHECK-NOT: arith.cmpi
// CHECK: return %[[XNOR]], %[[XOR]], %[[NA_AND_B]], %[[NA_OR_B]], %[[A_AND_NB]], %[[A_OR_NB]], %[[A_AND_NB]], %[[A_OR_NB]], %[[NA_AND_B]], %[[NA_OR_B]] :
func.func @i1_compare_pair(%a: i1, %b: i1) -> (i1, i1, i1, i1, i1, i1, i1, i1, i1, i1) {
  %0 = arith.cmpi eq, %a, %b : i1
  %1 = arith.cmpi ne, %a, %b : i1
  %2 = arith.cmpi ult, %a, %b : i1
  %3 = arith.cmpi ule, %a, %b : i1
  %4 = arith.cmpi ugt, %a, %b : i1
  %5 = arith.cmpi uge, %a, %b : i1
  %6 = arith.cmpi slt, %a, %b : i1
  %7 = arith.cmpi sle, %a, %b : i1
  %8 = arith.cmpi sgt, %a, %b : i1
  %9 = arith.cmpi sge, %a, %b : i1
  return %0, %1, %2, %3, %4, %5, %6, %7, %8, %9 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
}

// De Morgan and complement absorption hold bitwise for any integer, index or
// vector type whose negation is xori with all ones: ~p | ~q = ~(p & q),
// ~p & ~q = ~(p | q), x | (~x & y) = x | y and x & (~x | y) = x & y.
// CHECK-LABEL: func.func @de_morgan(
// CHECK-SAME: %[[P:.*]]: i8, %[[Q:.*]]: i8, %[[V:.*]]: vector<4xi8>, %[[W:.*]]: vector<4xi8>, %[[I:.*]]: index, %[[J:.*]]: index)
// CHECK-DAG: %[[ONES:.*]] = arith.constant -1 : i8
// CHECK-DAG: %[[VONES:.*]] = arith.constant dense<-1> : vector<4xi8>
// CHECK-DAG: %[[IONES:.*]] = arith.constant -1 : index
// CHECK-DAG: %[[PQ_AND:.*]] = arith.andi %[[P]], %[[Q]] : i8
// CHECK-DAG: %[[NAND:.*]] = arith.xori %[[PQ_AND]], %[[ONES]] : i8
// CHECK-DAG: %[[PQ_OR:.*]] = arith.ori %[[P]], %[[Q]] : i8
// CHECK-DAG: %[[NOR:.*]] = arith.xori %[[PQ_OR]], %[[ONES]] : i8
// CHECK-DAG: %[[VW_AND:.*]] = arith.andi %[[V]], %[[W]] : vector<4xi8>
// CHECK-DAG: %[[VNAND:.*]] = arith.xori %[[VW_AND]], %[[VONES]] : vector<4xi8>
// CHECK-DAG: %[[IJ_OR:.*]] = arith.ori %[[I]], %[[J]] : index
// CHECK-DAG: %[[INOR:.*]] = arith.xori %[[IJ_OR]], %[[IONES]] : index
// CHECK: return %[[NAND]], %[[NOR]], %[[PQ_OR]], %[[PQ_AND]], %[[VNAND]], %[[INOR]] :
func.func @de_morgan(%p: i8, %q: i8, %v: vector<4xi8>, %w: vector<4xi8>, %i: index, %j: index) -> (i8, i8, i8, i8, vector<4xi8>, index) {
  %ones = arith.constant -1 : i8
  %np = arith.xori %p, %ones : i8
  %nq = arith.xori %q, %ones : i8
  %0 = arith.ori %np, %nq : i8
  %np2 = arith.xori %p, %ones : i8
  %nq2 = arith.xori %q, %ones : i8
  %1 = arith.andi %np2, %nq2 : i8
  %np3 = arith.xori %p, %ones : i8
  %and = arith.andi %np3, %q : i8
  %2 = arith.ori %p, %and : i8
  %np4 = arith.xori %p, %ones : i8
  %or = arith.ori %np4, %q : i8
  %3 = arith.andi %p, %or : i8
  %vones = arith.constant dense<-1> : vector<4xi8>
  %nv = arith.xori %v, %vones : vector<4xi8>
  %nw = arith.xori %w, %vones : vector<4xi8>
  %4 = arith.ori %nv, %nw : vector<4xi8>
  %iones = arith.constant -1 : index
  %ni = arith.xori %i, %iones : index
  %nj = arith.xori %j, %iones : index
  %5 = arith.andi %ni, %nj : index
  return %0, %1, %2, %3, %4, %5 : i8, i8, i8, i8, vector<4xi8>, index
}

// De Morgan would add an operation when both negations have other uses, and a
// vector select of constants compared with a constant has no scalar result.
// CHECK-LABEL: func.func @de_morgan_and_select_kept(
// CHECK: %[[NP:.*]] = arith.xori %arg0,
// CHECK: %[[NQ:.*]] = arith.xori %arg1,
// CHECK: arith.ori %[[NP]], %[[NQ]] : i8
// CHECK: arith.select
// CHECK: arith.cmpi eq
func.func @de_morgan_and_select_kept(%p: i8, %q: i8, %c: i1) -> (i8, i8, i8, vector<4xi1>) {
  %ones = arith.constant -1 : i8
  %np = arith.xori %p, %ones : i8
  %nq = arith.xori %q, %ones : i8
  %0 = arith.ori %np, %nq : i8
  %a = arith.constant dense<3> : vector<4xi8>
  %b = arith.constant dense<7> : vector<4xi8>
  %s = arith.select %c, %a, %b : vector<4xi8>
  %1 = arith.cmpi eq, %s, %a : vector<4xi8>
  return %0, %np, %nq, %1 : i8, i8, i8, vector<4xi1>
}

// A comparison with a constant outside the range of an extension is decided;
// an extended i1 compares as the bit or its negation; so does a select of two
// constants.
// CHECK-LABEL: func.func @i1_compare_two_values(
// CHECK-SAME: %[[X:.*]]: i2, %[[B:.*]]: i1, %[[C:.*]]: i1)
// CHECK-DAG: %[[TRUE:.*]] = arith.constant true
// CHECK-DAG: %[[FALSE:.*]] = arith.constant false
// CHECK-DAG: %[[NOTB:.*]] = arith.xori %[[B]], %{{.*}} : i1
// CHECK-NOT: arith.cmpi
// CHECK: return %[[TRUE]], %[[FALSE]], %[[TRUE]], %[[TRUE]], %[[B]], %[[NOTB]], %[[B]], %[[C]], %[[C]], %[[TRUE]] :
func.func @i1_compare_two_values(%x: i2, %b: i1, %c: i1) -> (i1, i1, i1, i1, i1, i1, i1, i1, i1, i1) {
  %zx = arith.extui %x : i2 to i32
  %sx = arith.extsi %x : i2 to i32
  %zb = arith.extui %b : i1 to i32
  %sb = arith.extsi %b : i1 to i32
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c4 = arith.constant 4 : i32
  %cm1 = arith.constant -1 : i32
  %cm3 = arith.constant -3 : i32
  %0 = arith.cmpi ult, %zx, %c4 : i32
  %1 = arith.cmpi eq, %zx, %c4 : i32
  %2 = arith.cmpi slt, %sx, %c2 : i32
  %3 = arith.cmpi ne, %sx, %cm3 : i32
  %4 = arith.cmpi eq, %zb, %c1 : i32
  %5 = arith.cmpi eq, %zb, %c0 : i32
  %6 = arith.cmpi eq, %sb, %cm1 : i32
  %c3 = arith.constant 3 : i8
  %c7 = arith.constant 7 : i8
  %c9 = arith.constant 9 : i8
  %s = arith.select %c, %c3, %c7 : i8
  %7 = arith.cmpi eq, %s, %c3 : i8
  %8 = arith.cmpi ult, %s, %c7 : i8
  %9 = arith.cmpi ult, %s, %c9 : i8
  return %0, %1, %2, %3, %4, %5, %6, %7, %8, %9 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
}

// Absorption holds bitwise for any width. Constants inside an extension's
// range, non-i1 selects and selects of non-constants stay.
// CHECK-LABEL: func.func @absorption_and_kept(
// CHECK-SAME: %[[X:.*]]: i8, %[[Y:.*]]: i8
// CHECK: arith.cmpi ult
// CHECK: arith.select
// CHECK: return %[[X]], %[[X]], %{{.*}}, %{{.*}} :
func.func @absorption_and_kept(%x: i8, %y: i8, %n: i2, %c: i1) -> (i8, i8, i1, i8) {
  %or = arith.ori %x, %y : i8
  %and = arith.andi %x, %y : i8
  %0 = arith.andi %or, %x : i8
  %1 = arith.ori %x, %and : i8
  %zn = arith.extui %n : i2 to i32
  %c3 = arith.constant 3 : i32
  %2 = arith.cmpi ult, %zn, %c3 : i32
  %3 = arith.select %c, %x, %y : i8
  return %0, %1, %2, %3 : i8, i8, i1, i8
}

// `(r === 'X) || (r === 1'b1)` in two-state: the short-circuit diamond becomes
// select(r == 0, true, r), which is always true.
// CHECK-LABEL: func.func @i1_short_circuit(
// CHECK-NEXT: %[[TRUE:.*]] = arith.constant true
// CHECK-NEXT: return %[[TRUE]]
func.func @i1_short_circuit(%r: i1) -> i1 {
  %true = arith.constant true
  %false = arith.constant false
  %low = arith.cmpi eq, %r, %false : i1
  cf.cond_br %low, ^join(%true : i1), ^high
^high:
  cf.br ^join(%r : i1)
^join(%ok: i1):
  return %ok : i1
}
