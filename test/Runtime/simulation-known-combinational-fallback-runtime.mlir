// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-unroll-loops,simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},schedule-version-known-activations{minimum-benefit=1},convert-talos-sim-processes-to-llvm-coroutines)' 2> %t.log | talos-translate --mlir-to-llvmir | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: FileCheck %s --check-prefix=PLAN < %t.log
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --execution-tier=native | FileCheck %s
// RUN: %t.exe --execution-tier=bytecode | FileCheck %s

// The independently armed guards must reject an unknown input even after a
// previous invocation took the whole-body known path (IEEE 1800-2023 6.3.1).
// PLAN: talos known activation whole body: step
// PLAN: talos known activation: step segments=3/7
// CHECK: 00000110 00001111
// CHECK-NEXT: 00000110 xxxxxxxx
// CHECK-NEXT: xxxxxxxx 00001111

!c = !simulation.context
!v = !simulation.logic<8>
!r = !simulation.ref<!v>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
                   llvm.target_triple = "x86_64-unknown-linux-gnu",
                   native.optimization_level = 3 : i32, native.debug_timing,
                   schedule.native.max_inline_ops = 16 : i64} {
  simulation.design @fallback {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.step"
    simulation.storage.decl 0 in 0 : !v design
    simulation.storage.decl 1 in 0 : !v design
    simulation.storage.decl 2 in 0 : !v design
    simulation.storage.decl 3 in 0 : !v design
    simulation.func @__talos_root(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @initial(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %b = simulation.context.storage %ctx[1] : !r
      %oa = simulation.context.storage %ctx[2] : !r
      %ob = simulation.context.storage %ctx[3] : !r
      %two = simulation.logic.constant 2 : i8, 0 : i8 : !v
      %five = simulation.logic.constant 5 : i8, 0 : i8 : !v
      %x = simulation.logic.constant 0 : i8, 1 : i8 : !v
      %z = simulation.logic.constant 1 : i8, 1 : i8 : !v
      %out = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "%b %b"
      simulation.ref.store %two to %a : !v, !r
      simulation.ref.store %five to %b : !v, !r
      simulation.ref.store %two to %oa : !v, !r
      simulation.ref.store %five to %ob : !v, !r
      %ka, %kb = simulation.call @step(%ctx) : (!c) -> (!v, !v)
      simulation.display %ctx to %out(%fmt, %ka, %kb) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !v, !v
      simulation.ref.store %z to %b : !v, !r
      %za, %zb = simulation.call @step(%ctx) : (!c) -> (!v, !v)
      simulation.display %ctx to %out(%fmt, %za, %zb) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !v, !v
      simulation.ref.store %five to %b : !v, !r
      simulation.ref.store %x to %a : !v, !r
      %xa, %xb = simulation.call @step(%ctx) : (!c) -> (!v, !v)
      simulation.display %ctx to %out(%fmt, %xa, %xb) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !v, !v
      simulation.return
    }
    simulation.func private @step(%ctx: !c {simulation.capture_kind = 0 : i32})
        -> (!v, !v) attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64,
          schedule.eval.fusion_group = 0 : i32, schedule.eval.inductive_two_state} {
      %a = simulation.context.storage %ctx[0] : !r
      %b = simulation.context.storage %ctx[1] : !r
      %oa = simulation.context.storage %ctx[2] : !r
      %ob = simulation.context.storage %ctx[3] : !r
      %lo = arith.constant 0 : index
      %hi = arith.constant 12 : index
      %one = arith.constant 1 : index
      scf.for %i = %lo to %hi step %one {
        %v = simulation.ref.load %a : !r -> !v
        %d = simulation.logic.binary add %v, %v : !v
        %m = simulation.logic.binary xor %d, %v : !v
        simulation.ref.store %m to %oa : !v, !r
      }
      scf.for %i = %lo to %hi step %one {
        %v = simulation.ref.load %b : !r -> !v
        %d = simulation.logic.binary add %v, %v : !v
        %m = simulation.logic.binary xor %d, %v : !v
        simulation.ref.store %m to %ob : !v, !r
      }
      %x = simulation.ref.load %oa : !r -> !v
      %y = simulation.ref.load %ob : !r -> !v
      simulation.return %x, %y : !v, !v
    }
  }
}
