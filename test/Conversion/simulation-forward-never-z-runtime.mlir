// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true}))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FORWARD < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 12.5.1/12.5.3: X is significant in casez, Z is a
// wildcard, and casex treats both as wildcards. Removing a disjoint casez
// multiple-match branch must preserve its no-match result on X. The separate
// Z variable and undriven net must still report multiple matches.
// Both predecessors of a four-state SSA phi are exercised by the writer.
// FORWARD-LABEL: simulation.func private @safe(
// FORWARD-NOT: arith.constant 99
// FORWARD: arith.constant 77
// FORWARD-LABEL: simulation.func private @possible_z(
// FORWARD: arith.constant 99
// FORWARD: arith.constant 77
// FORWARD-LABEL: simulation.func private @casex(
// FORWARD: arith.constant 99
// OUTPUT: never-z X 77 99 99 1 99
// OUTPUT: never-z known 1 1

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @never_z_runtime {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "main"
    simulation.code_unit.decl 3 in 0 function hierarchy "safe"
    simulation.code_unit.decl 4 in 0 function hierarchy "possible_z"
    simulation.code_unit.decl 5 in 0 function hierarchy "casex"
    simulation.code_unit.decl 6 in 0 function hierarchy "exact"
    simulation.code_unit.decl 7 in 0 function hierarchy "net_z"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @exercise(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @safe(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
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
    simulation.func private @possible_z(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %r = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
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
    simulation.func private @casex(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
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
    simulation.func private @exact(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %r = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
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
    simulation.func private @net_z(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %r = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %x = simulation.net.read %r : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
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
    simulation.code_unit.decl 8 in 0 function hierarchy "write_with_phi"
    simulation.func private @write_with_phi(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 8 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      %known = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %choose, ^first, ^second
    ^first:
      cf.br ^join(%known : !simulation.logic<4>)
    ^second:
      cf.br ^join(%x : !simulation.logic<4>)
    ^join(%joined: !simulation.logic<4>):
      simulation.ref.store %joined to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
    simulation.func private @exercise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %safe = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %unsafe = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %x = simulation.logic.constant 0 : i4, 15 : i4 : !simulation.logic<4>
      %z = simulation.logic.constant 15 : i4, 15 : i4 : !simulation.logic<4>
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %one = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %false = arith.constant false
      simulation.call @write_with_phi(%ctx, %false) : (!simulation.context, i1) -> ()
      simulation.ref.store %z to %unsafe : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %a = simulation.call @safe(%ctx) : (!simulation.context) -> i32
      %b = simulation.call @possible_z(%ctx) : (!simulation.context) -> i32
      %c = simulation.call @casex(%ctx) : (!simulation.context) -> i32
      %d = simulation.call @exact(%ctx) : (!simulation.context) -> i32
      %e = simulation.call @net_z(%ctx) : (!simulation.context) -> i32
      %stdout = arith.constant 1 : i32
      %text = simulation.bytes.constant "never-z X %0d %0d %0d %0d %0d"
      simulation.display %ctx to %stdout(%text, %a, %b, %c, %d, %e) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0, 0] : !simulation.bytes, i32, i32, i32, i32, i32
      %true = arith.constant true
      simulation.call @write_with_phi(%ctx, %true) : (!simulation.context, i1) -> ()
      %f = simulation.call @safe(%ctx) : (!simulation.context) -> i32
      simulation.ref.store %one to %safe : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %g = simulation.call @safe(%ctx) : (!simulation.context) -> i32
      %known = simulation.bytes.constant "never-z known %0d %0d"
      simulation.display %ctx to %stdout(%known, %f, %g) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i32, i32
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
