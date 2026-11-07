// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{max-members=2 grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FUSED --implicit-check-not='schedule = convergence' < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// Each source-ordered process pair has a publication DAG. Both A and C are
// strictly repeatable and have a dead watch on the other pair's repeated output.
// B/D's repeated stores prevent assuming their composite is repeatable.
// Retaining the dead watches in their union waits would form a new event cycle:
// AB's B=0;B=I+1 wakes CD, whose D=0;D=X+1 wakes AB, forever.
// IEEE 1800-2023 4.3 permits suppressing the original strict member's
// unobservable wake; 4.6/9.4.2 still govern B/D's source publications. Construct
// each wait from per-member effective lanes before union and any later store
// simplification, so both kernels stay fused and their rebuilt event graph is
// acyclic. Initial #0 and settled later results remain correct
// (4.4.2.2/4.4.2.3, 9.2.2.2).
// FUSED-LABEL: simulation.func @root(
// FUSED-COUNT-2: simulation.spawn @__talos_region_kernel_
// FUSED: simulation.return
// FUSED-LABEL: simulation.func private @__talos_region_kernel_0_0(
// FUSED: %[[I:[a-zA-Z0-9_]+]] = simulation.context.storage %{{.*}}[0]
// FUSED-NOT: simulation.context.storage %{{.*}}[6]
// FUSED: simulation.suspend.any %[[I]] edges [0]
// FUSED-NOT: simulation.suspend
// FUSED-LABEL: simulation.func private @__talos_region_kernel_1_0(
// FUSED: %[[X:[a-zA-Z0-9_]+]] = simulation.context.storage %{{.*}}[4]
// FUSED-NOT: simulation.context.storage %{{.*}}[2]
// FUSED: simulation.suspend.any %[[X]] edges [0]
// FUSED-NOT: simulation.suspend
// OUTPUT: {{^}}settled 1 1{{$}}
// OUTPUT: {{^}}settled 2 2{{$}}

!ref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @watch_composition {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "c"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "d"
    simulation.code_unit.decl 5 in 0 always hierarchy "clock_i"
    simulation.code_unit.decl 6 in 0 always hierarchy "clock_x"
    simulation.code_unit.decl 7 in 0 initial hierarchy "check"
    simulation.code_unit.decl 100 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 100 : i64} {
      %ci = simulation.spawn @clock_i(%ctx) : !simulation.context -> !simulation.process
      %cx = simulation.spawn @clock_x(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @c(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @d(%ctx) : !simulation.context -> !simulation.process
      %check = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %i = simulation.context.storage %ctx[0] : !ref
      %address = simulation.context.storage %ctx[1] : !ref
      %bank = simulation.context.storage %ctx[2] : !ref
      %output = simulation.context.storage %ctx[3] : !ref
      %dead = simulation.context.storage %ctx[6] : !ref
      cf.br ^body
    ^body:
      %result = simulation.ref.load %bank : !ref -> i8
      simulation.ref.store %result to %output : i8, !ref
      %input = simulation.ref.load %i : !ref -> i8
      simulation.ref.store %input to %address : i8, !ref
      simulation.suspend.any %i, %bank, %dead edges [0, 0, 0] to ^body : !ref, !ref, !ref
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !ref
      %bank = simulation.context.storage %ctx[2] : !ref
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !ref -> i8
      %zero = arith.constant 0 : i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %zero to %bank : i8, !ref
      simulation.ref.store %next to %bank : i8, !ref
      simulation.suspend.change %address to ^body : !ref
    }
    simulation.func @c(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %x = simulation.context.storage %ctx[4] : !ref
      %left = simulation.context.storage %ctx[5] : !ref
      %right = simulation.context.storage %ctx[6] : !ref
      %output = simulation.context.storage %ctx[7] : !ref
      %dead = simulation.context.storage %ctx[2] : !ref
      cf.br ^body
    ^body:
      %result = simulation.ref.load %right : !ref -> i8
      simulation.ref.store %result to %output : i8, !ref
      %input = simulation.ref.load %x : !ref -> i8
      simulation.ref.store %input to %left : i8, !ref
      simulation.suspend.any %x, %right, %dead edges [0, 0, 0] to ^body : !ref, !ref, !ref
    }
    simulation.func @d(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %left = simulation.context.storage %ctx[5] : !ref
      %right = simulation.context.storage %ctx[6] : !ref
      cf.br ^body
    ^body:
      %value = simulation.ref.load %left : !ref -> i8
      %zero = arith.constant 0 : i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %zero to %right : i8, !ref
      simulation.ref.store %next to %right : i8, !ref
      simulation.suspend.change %left to ^body : !ref
    }
    simulation.func @clock_i(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      %input = simulation.context.storage %ctx[0] : !ref
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^tick
    ^tick:
      %old = simulation.ref.load %input : !ref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %input : i8, !ref
      cf.br ^wait
    }
    simulation.func @clock_x(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 6 : i64} {
      %input = simulation.context.storage %ctx[4] : !ref
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 7
      simulation.suspend.delay %delay to ^tick
    ^tick:
      %old = simulation.ref.load %input : !ref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %input : i8, !ref
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %a = simulation.context.storage %ctx[3] : !ref
      %c = simulation.context.storage %ctx[7] : !ref
      %zero = simulation.time.constant 0
      simulation.suspend.delay %zero to ^initial
    ^initial:
      %av = simulation.ref.load %a : !ref -> i8
      %cv = simulation.ref.load %c : !ref -> i8
      %format = simulation.bytes.constant "settled %0d %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%format, %av, %cv) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %delay = simulation.time.constant 8
      simulation.suspend.delay %delay to ^later
    ^later:
      %a2 = simulation.ref.load %a : !ref -> i8
      %c2 = simulation.ref.load %c : !ref -> i8
      %format2 = simulation.bytes.constant "settled %0d %0d"
      %stdout2 = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout2(%format2, %a2, %c2) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
