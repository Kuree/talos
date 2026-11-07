// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-fuse-compute-fragments{body-fusion=true},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,schedule-plan-combinational-statements{component-sections=true grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FUSED < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 4.3/4.6/9.4.2: recover the complete producer/observer
// cohort beside preserved C/D feedback. After initialization (9.2.2.2),
// change producer input I, then only observer input X. The union wake must
// update the observer while leaving the producer result stable. Check startup
// in Inactive after #0 (4.4.2.2/4.4.2.3), then sample settled later time slots.
// Repair after ordinary body fusion, with evaluator cloning deferred until
// the final materialization. Native lowering must consume the repaired actors
// and keep the pre-existing kernel and genuine feedback executors. The new
// kernel gets its continuation from the graph rebuild, so native lowering
// must also support its direct fragment without an early EvalBody clone.
// FUSED-LABEL: simulation.func @root(
// FUSED: simulation.spawn @already_kernel
// FUSED-NEXT: {{.*}}simulation.spawn @__talos_region_kernel_0_0
// FUSED-NEXT: {{.*}}simulation.spawn @c
// FUSED-NEXT: {{.*}}simulation.spawn @d
// FUSED-NEXT: {{.*}}simulation.spawn @check
// FUSED-NEXT: simulation.return
// FUSED-LABEL: simulation.func private @__talos_region_kernel_0_0(
// FUSED-NOT: schedule.eval.body
// FUSED: simulation.suspend.any
// FUSED-NOT: simulation.func {{.*}}@__talos_region_kernel_0_0.__talos_eval_body
// OUTPUT: {{^}}settled 1 1{{$}}
// OUTPUT: {{^}}settled 2 2{{$}}
// OUTPUT: {{^}}settled 2 3{{$}}

!r = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @recovered_observer_runtime {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.storage.decl 8 in 0 : i8 design
    simulation.storage.decl 9 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "c"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "d"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "already_kernel"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "observer"

    simulation.code_unit.decl 8 in 0 always hierarchy "clock_i"
    simulation.code_unit.decl 9 in 0 always hierarchy "clock_x"
    simulation.code_unit.decl 10 in 0 initial hierarchy "check"
    simulation.code_unit.decl 100 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 100 : i64} {
      %ci = simulation.spawn @clock_i(%ctx) : !simulation.context -> !simulation.process
      %cx = simulation.spawn @clock_x(%ctx) : !simulation.context -> !simulation.process
      %old = simulation.spawn @already_kernel(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @c(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @d(%ctx) : !simulation.context -> !simulation.process
      %observer = simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process
      %check = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process

      simulation.return
    }
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %i = simulation.context.storage %ctx[0] : !r
      %address = simulation.context.storage %ctx[1] : !r
      %bank = simulation.context.storage %ctx[2] : !r
      %output = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %result = simulation.ref.load %bank : !r -> i8
      simulation.ref.store %result to %output : i8, !r
      %input = simulation.ref.load %i : !r -> i8
      simulation.ref.store %input to %address : i8, !r
      simulation.suspend.any %i, %bank edges [0, 0] to ^body : !r, !r
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %bank = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      %zero = arith.constant 0 : i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %zero to %bank : i8, !r
      simulation.ref.store %next to %bank : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
    simulation.func @c(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %previous = simulation.context.storage %ctx[5] : !r
      %output = simulation.context.storage %ctx[4] : !r
      cf.br ^body
    ^body:
      %x = simulation.ref.load %previous : !r -> i8
      %y = simulation.ref.load %address : !r -> i8
      %value = arith.andi %x, %y : i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.any %address, %previous edges [0, 0] to ^body : !r, !r
    }
    simulation.func @d(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.storage %ctx[4] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %bank = simulation.context.storage %ctx[2] : !r
      %other = simulation.context.storage %ctx[8] : !r
      %output = simulation.context.storage %ctx[9] : !r
      cf.br ^body
    ^body:
      %b = simulation.ref.load %bank : !r -> i8
      %x = simulation.ref.load %other : !r -> i8
      %value = arith.xori %b, %x : i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.any %bank, %other edges [0, 0] to ^body : !r, !r
    }
    simulation.func private @already_kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64, schedule.native.region_body} {
      %input = simulation.context.storage %ctx[6] : !r
      %output = simulation.context.storage %ctx[7] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }

    simulation.func @clock_i(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 8 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^tick
    ^tick:
      %old = simulation.ref.load %input : !r -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %input : i8, !r
      cf.br ^wait
    }
    simulation.func @clock_x(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 9 : i64} {
      %input = simulation.context.storage %ctx[8] : !r
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 7
      simulation.suspend.delay %delay to ^tick
    ^tick:
      %old = simulation.ref.load %input : !r -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %input : i8, !r
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 10 : i64} {
      %producer = simulation.context.storage %ctx[3] : !r
      %observer = simulation.context.storage %ctx[9] : !r
      %zero = simulation.time.constant 0
      simulation.suspend.delay %zero to ^first
    ^first:
      %a0 = simulation.ref.load %producer : !r -> i8
      %b0 = simulation.ref.load %observer : !r -> i8
      %format0 = simulation.bytes.constant "settled %0d %0d"
      %stdout0 = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout0(%format0, %a0, %b0) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %delay0 = simulation.time.constant 6
      simulation.suspend.delay %delay0 to ^producer_changed
    ^producer_changed:
      %a1 = simulation.ref.load %producer : !r -> i8
      %b1 = simulation.ref.load %observer : !r -> i8
      %format1 = simulation.bytes.constant "settled %0d %0d"
      %stdout1 = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout1(%format1, %a1, %b1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %delay1 = simulation.time.constant 2
      simulation.suspend.delay %delay1 to ^observer_changed
    ^observer_changed:
      %a2 = simulation.ref.load %producer : !r -> i8
      %b2 = simulation.ref.load %observer : !r -> i8
      %format2 = simulation.bytes.constant "settled %0d %0d"
      %stdout2 = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout2(%format2, %a2, %b2) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
