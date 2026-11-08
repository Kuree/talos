// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph,talos-sim-specialize-static-state-nba),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir
// RUN: FileCheck %s --check-prefix=LOWER < %t.mlir
// RUN: talos-translate --mlir-to-llvmir %t.mlir -o %t.ll
// RUN: %llvm_dist/bin/opt %t.ll -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>,verify' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: %llvm_dist/bin/opt %t.ll -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>,verify' | %llc -filetype=obj -relocation-model=pic -o %t.o3.o
// RUN: %target_cxx %t.o3.o %runtime_link_flags -o %t.o3.exe && %t.o3.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: %t.o3.exe --execution-tier=bytecode | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 6.3.1/4.6/9.4.2: copying known 256-bit values may leave
// an already-known destination's unknown plane untouched. A known RHS alone
// must clear an old X/Z plane, including when no value-plane bit changes.
// Bit zero changes Z -> 1 in that case and must publish its posedge. Ordinary
// copies also preserve mixed X/Z patterns across machine-word boundaries.
// Public helpers keep a dynamic destination ABI and exercise fused bulk copy.
// OUTPUT: copies 1 1 1 1 1 1 edges 1
!word = !simulation.logic<256>
!ref = !simulation.ref<!word>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", native.optimization_level = 3 : i32} {
  simulation.design @known_memory_runtime {
    simulation.scope.decl 0 hierarchy "top"
    simulation.storage.decl 0 in 0 : !word design hierarchy "top.src"
    simulation.storage.decl 1 in 0 : !word design hierarchy "top.dst"
    simulation.storage.decl 2 in 0 : i32 design hierarchy "top.edges"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.run"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.known_dynamic"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.rhs_dynamic"
    simulation.code_unit.decl 5 in 0 function hierarchy "top.canonical_dynamic"
    simulation.code_unit.decl 6 in 0 function hierarchy "top.known_static"
    simulation.code_unit.decl 7 in 0 always hierarchy "top.watch"
    simulation.func @__talos_root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %watch = simulation.spawn @watch(%ctx) : !simulation.context -> !simulation.process
      %run = simulation.spawn @run(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @run(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %src = simulation.context.storage %ctx[0] : !ref
      %dst = simulation.context.storage %ctx[1] : !ref
      %known = simulation.logic.constant 514631507721405312519378913364952599437893773118507240507895286931579072255 : i256, 0 : i256 : !word
      %mixed = simulation.logic.constant 514631507721405312519378913364952599437893773118507240507895286931579072255 : i256, 450552876409790644016299190121423167346753885412210415464505612233128389205 : i256 : !word
      %other = simulation.logic.constant 53521676831783428993818858570901171587954391729951694925007823118004434006144 : i256, 0 : i256 : !word
      simulation.ref.store %known to %src : !word, !ref
      simulation.ref.store %other to %dst : !word, !ref
      %delay0 = simulation.time.constant 1
      simulation.suspend.delay %delay0 to ^copy {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^copy:
      simulation.call @known_dynamic(%ctx, %dst) : (!simulation.context, !ref) -> ()
      %r0 = simulation.ref.load %dst : !ref -> !word
      %ok0 = simulation.logic.compare case_eq %r0, %known : (!word, !word) -> i1
      %delay1 = simulation.time.constant 1
      simulation.suspend.delay %delay1 to ^clear {site = #schedule.continuation<id = 2>, timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^clear:
      // Value bits are identical before/after this copy; only U changes.
      simulation.ref.store %mixed to %dst : !word, !ref
      simulation.call @rhs_dynamic(%ctx, %dst) : (!simulation.context, !ref) -> ()
      %r1 = simulation.ref.load %dst : !ref -> !word
      %ok1 = simulation.logic.compare case_eq %r1, %known : (!word, !word) -> i1
      %delay2 = simulation.time.constant 1
      simulation.suspend.delay %delay2 to ^finish {site = #schedule.continuation<id = 3>, timing = #schedule.timing_site<id = 2, kind = calendar>}
    ^finish:
      simulation.ref.store %mixed to %src : !word, !ref
      simulation.call @canonical_dynamic(%ctx, %dst) : (!simulation.context, !ref) -> ()
      %r2 = simulation.ref.load %dst : !ref -> !word
      %ok2 = simulation.logic.compare case_eq %r2, %mixed : (!word, !word) -> i1
      simulation.ref.store %other to %src : !word, !ref
      simulation.call @canonical_dynamic(%ctx, %dst) : (!simulation.context, !ref) -> ()
      %r3 = simulation.ref.load %dst : !ref -> !word
      %ok3 = simulation.logic.compare case_eq %r3, %other : (!word, !word) -> i1
      simulation.call @known_dynamic(%ctx, %src) : (!simulation.context, !ref) -> ()
      %r4 = simulation.ref.load %src : !ref -> !word
      %ok4 = simulation.logic.compare case_eq %r4, %other : (!word, !word) -> i1
      simulation.call @known_static(%ctx) : (!simulation.context) -> ()
      %r5 = simulation.ref.load %dst : !ref -> !word
      %ok5 = simulation.logic.compare case_eq %r5, %other : (!word, !word) -> i1
      %counter = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %count = simulation.ref.load %counter : !simulation.ref<i32> -> i32
      %two = arith.constant 2 : i32
      %edges_ok = arith.cmpi eq, %count, %two : i32
      %fmt = simulation.bytes.constant "copies %0d %0d %0d %0d %0d %0d edges %0d"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%fmt, %ok0, %ok1, %ok2, %ok3, %ok4, %ok5, %edges_ok) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1, i1, i1, i1
      %exit = arith.constant 0 : i32
      simulation.finish %ctx, %exit
      simulation.return
    }
    // LOWER-LABEL: llvm.func @known_dynamic(
    // LOWER-NOT: @__talos_state_unknown
    // LOWER: llvm.call @talos_rt_v1_native_state_store_plane
    // LOWER-NOT: @__talos_state_unknown
    // LOWER: llvm.return
    simulation.func @known_dynamic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %dst: !ref {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %src = simulation.context.storage %ctx[0] : !ref
      %v = simulation.ref.load %src {schedule.native.known_read} : !ref -> !word
      simulation.ref.store %v to %dst {schedule.native.known_store} : !word, !ref
      simulation.return
    }
    // LOWER-LABEL: llvm.func @rhs_dynamic(
    // LOWER: @__talos_state_unknown
    // LOWER-COUNT-2: llvm.call @talos_rt_v1_native_state_store_plane
    // LOWER: llvm.return
    simulation.func @rhs_dynamic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %dst: !ref {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %src = simulation.context.storage %ctx[0] : !ref
      %v = simulation.ref.load %src {schedule.native.known_read} : !ref -> !word
      simulation.ref.store %v to %dst : !word, !ref
      simulation.return
    }
    // LOWER-LABEL: llvm.func @canonical_dynamic(
    // LOWER: @__talos_state_unknown
    // LOWER-COUNT-2: llvm.call @talos_rt_v1_native_state_store_plane
    // LOWER: llvm.return
    simulation.func @canonical_dynamic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %dst: !ref {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %src = simulation.context.storage %ctx[0] : !ref
      %v = simulation.ref.load %src : !ref -> !word
      simulation.ref.store %v to %dst : !word, !ref
      simulation.return
    }
    // LOWER-LABEL: llvm.func @known_static(
    // LOWER: llvm.return
    simulation.func @known_static(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %src = simulation.context.storage %ctx[0] : !ref
      %dst = simulation.context.storage %ctx[1] : !ref
      %v = simulation.ref.load %src {schedule.native.known_read} : !ref -> !word
      simulation.ref.store %v to %dst {schedule.native.known_store} : !word, !ref
      simulation.return
    }
    simulation.func private @watch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 7 : i64} {
      %dst = simulation.context.storage %ctx[1] : !ref
      %bit = simulation.ref.extract %dst from 0 : !ref -> !simulation.ref<!simulation.logic<1>>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %bit to ^count {site = #schedule.continuation<id = 4>} : !simulation.ref<!simulation.logic<1>>
    ^count:
      %counter = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %old = simulation.ref.load %counter : !simulation.ref<i32> -> i32
      %one = arith.constant 1 : i32
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %counter : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}
