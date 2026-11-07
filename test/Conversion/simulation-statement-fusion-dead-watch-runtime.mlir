// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{max-members=2 grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FINE < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// The producer writes the high nibble of a root watched in full; only its
// low nibble is live in the outside observer. The process cycle is a DAG.
// The observer keeps
// its original broad source wait, while the two dependent processes fuse.
// IEEE 1800-2023 4.3 permits the equivalent algorithm; 4.6(a) still requires
// source-local snapshots and publications, certified by the existing slicer.
// Startup evaluation (4.9.1, 9.2.2.2) and Active-before-Inactive ordering
// (4.4.2.2/4.4.2.3) must settle the outputs before the initial #0 sample.
// FINE-LABEL: simulation.func @root(
// FINE: simulation.spawn @__talos_region_kernel_0_0
// FINE: simulation.spawn @overwrite
// FINE: simulation.return
// OUTPUT: {{^}}settled 16{{$}}
// OUTPUT: {{^}}settled 32{{$}}

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @ordered_dead_watch {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "overwrite"
    simulation.code_unit.decl 4 in 0 always hierarchy "sample"
    simulation.code_unit.decl 5 in 0 always hierarchy "clock"
    simulation.code_unit.decl 6 in 0 initial hierarchy "check"
    simulation.code_unit.decl 100 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 100 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %zero = arith.constant 0 : i8
      simulation.ref.store %zero to %input : i8, !simulation.ref<i8>
      %clock = simulation.spawn @clock(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @overwrite(%ctx) : !simulation.context -> !simulation.process
      %check = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %r = arith.addi %a, %one : i8
      %part = simulation.ref.extract %result from 4 : !simulation.ref<i8> -> !simulation.ref<i4>
      %nibble = arith.trunci %r : i8 to i4
      simulation.ref.store %nibble to %part : i4, !simulation.ref<i4>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @overwrite(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %extra = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %scratch = simulation.context.storage %ctx[5] : !simulation.ref<i8>
      %output = simulation.context.storage %ctx[6] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %base = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %low_ref = simulation.ref.extract %extra from 0 : !simulation.ref<i8> -> !simulation.ref<i4>
      %low = simulation.ref.load %low_ref : !simulation.ref<i4> -> i4
      %extended = arith.extui %low : i4 to i8
      %new = arith.addi %base, %extended : i8
      simulation.ref.store %new to %scratch : i8, !simulation.ref<i8>
      simulation.ref.store %new to %output : i8, !simulation.ref<i8>
      simulation.suspend.any %input, %extra edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^tick
    ^tick:
      %old = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %input : i8, !simulation.ref<i8>
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %output = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      %zero = simulation.time.constant 0
      simulation.suspend.delay %zero to ^initial
    ^initial:
      %first = simulation.ref.load %output : !simulation.ref<i8> -> i8
      %format = simulation.bytes.constant "settled %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%format, %first) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      %delay = simulation.time.constant 6
      simulation.suspend.delay %delay to ^later
    ^later:
      %second = simulation.ref.load %output : !simulation.ref<i8> -> i8
      %later_format = simulation.bytes.constant "settled %0d"
      %later_stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %later_stdout(%later_format, %second) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
