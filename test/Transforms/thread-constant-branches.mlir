// RUN: talos-opt %s --talos-thread-constant-branches | FileCheck %s

// A predicate answered on several paths merges its answers in ^decide, which
// holds only the branch on them. The cached and backed-off answers are
// constants: their edges go straight to the successor they select, with the
// successor's operands taken from the edge. The runtime answer still decides
// at ^decide, which keeps its other edge.
// CHECK-LABEL: llvm.func @gate(
// CHECK-SAME: %[[CLEAN:.*]]: i1, %[[WAITING:.*]]: i1, %[[ANSWER:.*]]: i1, %[[W:.*]]: i64)
// CHECK: llvm.cond_br %[[CLEAN]] weights([1048575, 1]), ^[[COPY:bb[0-9]+]](%[[W]] : i64), ^[[SLOW:bb[0-9]+]]
// CHECK: ^[[SLOW]]:
// CHECK-NEXT: llvm.cond_br %[[WAITING]], ^[[WAIT:bb[0-9]+]], ^[[CALL:bb[0-9]+]]
// CHECK: ^[[WAIT]]:
// CHECK-NEXT: llvm.br ^[[BODY:bb[0-9]+]]{{$}}
// CHECK: ^[[CALL]]:
// CHECK-NEXT: llvm.br ^[[DECIDE:bb[0-9]+]](%[[ANSWER]], %[[W]] : i1, i64)
// CHECK: ^[[DECIDE]](%[[KNOWN:.*]]: i1, %[[V:.*]]: i64):
// CHECK-NEXT: llvm.cond_br %[[KNOWN]], ^[[COPY]](%[[V]] : i64), ^[[BODY]]
llvm.func @gate(%clean: i1, %waiting: i1, %answer: i1, %w: i64) {
  %true = llvm.mlir.constant(true) : i1
  %false = llvm.mlir.constant(false) : i1
  llvm.cond_br %clean weights([1048575, 1]), ^decide(%true, %w : i1, i64), ^slow
^slow:
  llvm.cond_br %waiting, ^wait, ^call
^wait:
  llvm.br ^decide(%false, %w : i1, i64)
^call:
  llvm.br ^decide(%answer, %w : i1, i64)
^decide(%known: i1, %v: i64):
  llvm.cond_br %known, ^copy(%v : i64), ^body
^copy(%x: i64):
  llvm.call @fast(%x) : (i64) -> ()
  llvm.return
^body:
  llvm.call @slow() : () -> ()
  llvm.return
}
llvm.func @fast(i64)
llvm.func @slow()

// A flag that later blocks test again is rebuilt on the bypassing path (SSA
// reconstruction): the re-test then sees the constant and takes one edge.
// CHECK-LABEL: llvm.func @retested(
// CHECK-NEXT: llvm.br ^[[A:bb[0-9]+]]{{$}}
// CHECK: ^[[A]]:
// CHECK-NEXT: llvm.call @slow()
// CHECK-NEXT: llvm.br ^[[JOIN:bb[0-9]+]]{{$}}
// CHECK: ^[[JOIN]]:
// CHECK-NEXT: llvm.br ^[[C:bb[0-9]+]]{{$}}
// CHECK-NOT: llvm.cond_br
// CHECK: llvm.return
llvm.func @retested() {
  %true = llvm.mlir.constant(true) : i1
  llvm.br ^decide(%true : i1)
^decide(%flag: i1):
  llvm.cond_br %flag, ^a, ^b
^a:
  llvm.call @slow() : () -> ()
  llvm.br ^join
^b:
  llvm.br ^join
^join:
  llvm.cond_br %flag, ^c, ^d
^c:
  llvm.call @slow() : () -> ()
  llvm.return
^d:
  llvm.return
}

// A guard: the cached answer bypasses the decision, and both arms of the
// decision rejoin before testing the flag again. Each arm fixes the flag (its
// branch decided it), so the rejoined test becomes a decision of its own and
// every arm goes straight to its outcome; only the runtime answer is tested.
// CHECK-LABEL: llvm.func @guard(
// CHECK-SAME: %[[CACHED:.*]]: i1, %[[ANSWER:.*]]: i1)
// CHECK-NEXT: llvm.cond_br %[[CACHED]], ^[[FASTARM:bb[0-9]+]], ^[[RUNTIME:bb[0-9]+]]
// CHECK: ^[[RUNTIME]]:
// CHECK-NEXT: llvm.br ^[[DECIDE:bb[0-9]+]](%[[ANSWER]] : i1)
// CHECK: ^[[DECIDE]](%[[FLAG:.*]]: i1):
// CHECK-NEXT: llvm.cond_br %[[FLAG]], ^[[FASTARM]], ^[[SLOWARM:bb[0-9]+]]
// CHECK: ^[[FASTARM]]:
// CHECK-NEXT: llvm.call @hot()
// CHECK-NEXT: llvm.br ^[[FASTEND:bb[0-9]+]]{{$}}
// CHECK: ^[[SLOWARM]]:
// CHECK-NEXT: llvm.call @slow()
// CHECK-NEXT: llvm.br ^[[SLOWEND:bb[0-9]+]]{{$}}
// CHECK: ^[[FASTEND]]:
// CHECK-NEXT: llvm.call @hot()
// CHECK: ^[[SLOWEND]]:
// CHECK-NEXT: llvm.call @slow()
llvm.func @guard(%cached: i1, %answer: i1) {
  %true = llvm.mlir.constant(true) : i1
  llvm.cond_br %cached, ^decide(%true : i1), ^runtime
^runtime:
  llvm.br ^decide(%answer : i1)
^decide(%flag: i1):
  llvm.cond_br %flag, ^a, ^b
^a:
  llvm.call @hot() : () -> ()
  llvm.br ^join
^b:
  llvm.call @slow() : () -> ()
  llvm.br ^join
^join:
  llvm.cond_br %flag, ^c, ^d
^c:
  llvm.call @hot() : () -> ()
  llvm.return
^d:
  llvm.call @slow() : () -> ()
  llvm.return
}
llvm.func @hot()

// The repaired flag has several uses, one an operand of the branch an edge
// is appended to: each use sees the definition reaching its own block.
// CHECK-LABEL: llvm.func @uses(
// CHECK: %[[FALSE:.*]] = llvm.mlir.constant(false) : i1
// CHECK: ^{{bb[0-9]+}}(%[[FLAG:.*]]: i1, %[[GO:.*]]: i1):
// CHECK-NEXT: llvm.cond_br %[[GO]], ^[[T:bb[0-9]+]](%[[FLAG]] : i1), ^
// CHECK: ^[[T]](%[[MERGED:.*]]: i1):
// CHECK-NEXT: llvm.call @use(%[[MERGED]])
// CHECK: llvm.cond_br %{{.*}}, ^[[T]](%[[FALSE]] : i1), ^[[Z:bb[0-9]+]](%[[MERGED]] : i1)
llvm.func @use(i1)
llvm.func @uses(%init: i1, %g: i1, %c: i1) {
  %false = llvm.mlir.constant(false) : i1
  %true = llvm.mlir.constant(true) : i1
  llvm.br ^h(%init, %g : i1, i1)
^h(%flag: i1, %go: i1):
  llvm.cond_br %go, ^t, ^x
^t:
  llvm.call @use(%flag) : (i1) -> ()
  llvm.br ^l
^l:
  llvm.cond_br %c, ^h(%false, %true : i1, i1), ^z(%flag : i1)
^z(%out: i1):
  llvm.call @use(%out) : (i1) -> ()
  llvm.return
^x:
  llvm.return
}

// A latch that passes the block's own argument back means its value at the
// latch: that edge waits for the repair and then carries the merged flag.
// CHECK-LABEL: llvm.func @latches(
// CHECK-SAME: %[[INIT:[^:]*]]: i1, %[[X:[^:]*]]: i1, %[[C:[^:]*]]: i1, %[[D:[^:]*]]: i1)
// CHECK-NEXT: llvm.br ^[[T:bb[0-9]+]](%[[INIT]] : i1)
// CHECK: ^[[T]](%[[FLAG:.*]]: i1):
// CHECK-NEXT: llvm.call @use(%[[FLAG]])
// CHECK: llvm.br ^[[T]](%[[X]] : i1)
// CHECK: llvm.cond_br %[[D]], ^[[T]](%[[FLAG]] : i1), ^
llvm.func @latches(%init: i1, %x: i1, %c: i1, %d: i1) {
  %true = llvm.mlir.constant(true) : i1
  llvm.br ^h(%init, %true : i1, i1)
^h(%flag: i1, %go: i1):
  llvm.cond_br %go, ^t, ^exit
^t:
  llvm.call @use(%flag) : (i1) -> ()
  llvm.cond_br %c, ^l1, ^l2
^l1:
  llvm.br ^h(%x, %true : i1, i1)
^l2:
  llvm.cond_br %d, ^h(%flag, %true : i1, i1), ^exit
^exit:
  llvm.return
}

// Arguments swapped around a latch: repairing one would append a use of the
// other after its own repair. The latch threads once both are rebuilt.
// CHECK-LABEL: llvm.func @swapped(
// CHECK-SAME: %[[A0:[^:]*]]: i1, %[[B0:[^:]*]]: i1, %[[C:[^:]*]]: i1)
// CHECK-NEXT: llvm.br ^[[T:bb[0-9]+]](%[[A0]], %[[B0]] : i1, i1)
// CHECK: ^[[T]](%[[A:.*]]: i1, %[[B:.*]]: i1):
// CHECK-NEXT: llvm.call @use(%[[A]])
// CHECK-NEXT: llvm.call @use(%[[B]])
// CHECK-NEXT: llvm.cond_br %[[C]], ^[[T]](%[[B]], %[[A]] : i1, i1), ^
llvm.func @swapped(%a0: i1, %b0: i1, %c: i1) {
  %true = llvm.mlir.constant(true) : i1
  llvm.br ^h(%a0, %b0, %true : i1, i1, i1)
^h(%a: i1, %b: i1, %go: i1):
  llvm.cond_br %go, ^t, ^exit
^t:
  llvm.call @use(%a) : (i1) -> ()
  llvm.call @use(%b) : (i1) -> ()
  llvm.cond_br %c, ^h(%b, %a, %true : i1, i1, i1), ^exit
^exit:
  llvm.return
}

// Equal constants defined in different predecessors merge into one in the
// entry block, which dominates the merge.
// CHECK-LABEL: llvm.func @constants(
// CHECK-NEXT: %[[TRUE:.*]] = llvm.mlir.constant(true) : i1
// CHECK-NEXT: %[[FALSE:.*]] = llvm.mlir.constant(false) : i1
// CHECK: llvm.br ^[[JOIN:bb[0-9]+]](%[[TRUE]] : i1)
// CHECK: llvm.br ^[[JOIN]](%[[FALSE]] : i1)
// CHECK: ^[[JOIN]](%[[FLAG:.*]]: i1):
// CHECK-NEXT: llvm.call @use(%[[FLAG]])
llvm.func @constants(%p: i1, %d: i1, %a: i1) {
  llvm.cond_br %p, ^p1, ^p2
^p1:
  %t1 = llvm.mlir.constant(true) : i1
  llvm.br ^decide(%t1 : i1)
^p2:
  %t2 = llvm.mlir.constant(true) : i1
  llvm.cond_br %d, ^decide(%t2 : i1), ^decide(%a : i1)
^decide(%flag: i1):
  llvm.cond_br %flag, ^x, ^y
^x:
  llvm.br ^join
^y:
  llvm.br ^join
^join:
  llvm.call @use(%flag) : (i1) -> ()
  llvm.return
}

// A use inside a nested region takes the definition reaching the block that
// holds it.
// CHECK-LABEL: func.func @nested(
// CHECK: cf.cond_br %{{.*}}, ^[[X:bb[0-9]+]](%{{.*}} : i1), ^
// CHECK: ^[[X]](%[[FLAG:.*]]: i1):
// CHECK-NEXT: scf.if
// CHECK-NEXT: func.call @used(%[[FLAG]])
func.func private @used(i1)
func.func @nested(%c: i1, %a: i1, %e: i1) {
  %true = arith.constant true
  cf.cond_br %c, ^decide(%true : i1), ^decide(%a : i1)
^decide(%flag: i1):
  cf.cond_br %flag, ^x, ^y
^x:
  scf.if %e {
    func.call @used(%flag) : (i1) -> ()
  }
  return
^y:
  return
}

// A block that computes before its branch is not a pure decision.
// CHECK-LABEL: llvm.func @computes(
// CHECK: llvm.br ^[[DECIDE:bb[0-9]+]](%{{.*}} : i1)
// CHECK: ^[[DECIDE]](%[[KNOWN:.*]]: i1):
// CHECK-NEXT: llvm.xor
llvm.func @computes(%c: i1) {
  %true = llvm.mlir.constant(true) : i1
  llvm.br ^decide(%true : i1)
^decide(%known: i1):
  %flip = llvm.xor %known, %c : i1
  llvm.cond_br %flip, ^a, ^b
^a:
  llvm.call @slow() : () -> ()
  llvm.return
^b:
  llvm.return
}

// Any terminator that reports its successor for constant operands threads
// the same way, here cf.cond_br.
// CHECK-LABEL: func.func @interface(
// CHECK: cf.cond_br %{{.*}}, ^[[ONE:bb[0-9]+]], ^[[TWO:bb[0-9]+]]
// CHECK: ^[[ONE]]:
// CHECK-NEXT: call @one()
// CHECK: ^[[TWO]]:
// CHECK-NEXT: call @two()
func.func private @one()
func.func private @two()
func.func @interface(%c: i1) {
  %true = arith.constant true
  %false = arith.constant false
  cf.cond_br %c, ^decide(%true : i1), ^decide(%false : i1)
^decide(%known: i1):
  cf.cond_br %known, ^one, ^two
^one:
  call @one() : () -> ()
  return
^two:
  call @two() : () -> ()
  return
}

// A constant circling a loop of decision blocks would move its edge forever:
// the pass stops at the rewrite limit and leaves valid branches behind.
// CHECK-LABEL: llvm.func @cycle(
// CHECK: llvm.return
llvm.func @cycle() {
  %true = llvm.mlir.constant(true) : i1
  llvm.br ^a(%true : i1)
^a(%k: i1):
  llvm.cond_br %k, ^b(%k : i1), ^exit
^b(%j: i1):
  llvm.cond_br %j, ^a(%j : i1), ^exit
^exit:
  llvm.return
}
