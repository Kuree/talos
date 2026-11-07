// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FUSED --implicit-check-not='simulation.spawn @copy_' --implicit-check-not='simulation.spawn @reader_' --implicit-check-not='simulation.spawn @writer_' < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 4.3/4.6/10.4.1: the output's bit65 precedes its observer
// and bit129 follows the resulting update. Each integer/packed copy needs two
// slices; those slices must read their corresponding source versions across
// the intervening store. Both bits cross a native word boundary. Sample the
// complete values after startup and subsequent input changes, keeping nonzero
// neighboring lanes on both sides of each window throughout the sequence.
// FUSED-LABEL: simulation.func @root(
// FUSED: simulation.spawn @__talos_region_kernel_0_0
// FUSED: simulation.spawn @__talos_region_kernel_1_0
// FUSED: simulation.return
// OUTPUT-COUNT-4: {{^}}integer lanes 1 1{{$}}

!packed = !simulation.packed_array<129 : 0 x i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @integer_copy_runtime {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i130 design
    simulation.storage.decl 1 in 0 : i130 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : !packed design
    simulation.storage.decl 4 in 0 : !packed design
    simulation.storage.decl 5 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "copy_integer"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "reader_integer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "writer_integer"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "copy_packed"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "reader_packed"
    simulation.code_unit.decl 6 in 0 always_comb hierarchy "writer_packed"
    simulation.code_unit.decl 10 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 11 in 0 initial hierarchy "drive"
    simulation.code_unit.decl 12 in 0 initial hierarchy "check"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 10 : i64} {
      %p0 = simulation.spawn @copy_integer(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @reader_integer(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @writer_integer(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @copy_packed(%ctx) : !simulation.context -> !simulation.process
      %p4 = simulation.spawn @reader_packed(%ctx) : !simulation.context -> !simulation.process
      %p5 = simulation.spawn @writer_packed(%ctx) : !simulation.context -> !simulation.process
      %p6 = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      %p7 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @copy_integer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i130>
      %output = simulation.context.storage %ctx[1] : !simulation.ref<i130>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i130> -> i130
      simulation.ref.store %value to %output : i130, !simulation.ref<i130>
      simulation.suspend.change %input to ^body : !simulation.ref<i130>
    }
    simulation.func @reader_integer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %whole = simulation.context.storage %ctx[1] : !simulation.ref<i130>
      %input = simulation.ref.extract %whole from 65 : !simulation.ref<i130> -> !simulation.ref<i1>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @writer_integer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %whole = simulation.context.storage %ctx[0] : !simulation.ref<i130>
      %output = simulation.ref.extract %whole from 129 : !simulation.ref<i130> -> !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @copy_packed(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.storage %ctx[3] : !simulation.ref<!packed>
      %output = simulation.context.storage %ctx[4] : !simulation.ref<!packed>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<!packed> -> !packed
      simulation.ref.store %value to %output : !packed, !simulation.ref<!packed>
      simulation.suspend.change %input to ^body : !simulation.ref<!packed>
    }
    simulation.func @reader_packed(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      %whole = simulation.context.storage %ctx[4] : !simulation.ref<!packed>
      %input = simulation.ref.extract %whole from 65 : !simulation.ref<!packed> -> !simulation.ref<i1>
      %output = simulation.context.storage %ctx[5] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @writer_packed(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
      %input = simulation.context.storage %ctx[5] : !simulation.ref<i1>
      %whole = simulation.context.storage %ctx[3] : !simulation.ref<!packed>
      %output = simulation.ref.extract %whole from 129 : !simulation.ref<!packed> -> !simulation.ref<i1>
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !simulation.ref<i1> -> i1
      simulation.ref.store %value to %output : i1, !simulation.ref<i1>
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 11 : i64} {
      %integer = simulation.context.storage %ctx[0] : !simulation.ref<i130>
      %a = simulation.ref.extract %integer from 65 : !simulation.ref<i130> -> !simulation.ref<i1>
      %packed = simulation.context.storage %ctx[3] : !simulation.ref<!packed>
      %b = simulation.ref.extract %packed from 65 : !simulation.ref<!packed> -> !simulation.ref<i1>
      %a_lo = simulation.ref.extract %integer from 0 : !simulation.ref<i130> -> !simulation.ref<i65>
      %a_hi = simulation.ref.extract %integer from 66 : !simulation.ref<i130> -> !simulation.ref<i63>
      %b_lo = simulation.ref.extract %packed from 0 : !simulation.ref<!packed> -> !simulation.ref<i65>
      %b_hi = simulation.ref.extract %packed from 66 : !simulation.ref<!packed> -> !simulation.ref<i63>
      %pattern_lo = arith.constant 18446744073709551617 : i65
      %pattern_hi = arith.constant 4611686018427387905 : i63
      %two = simulation.time.constant 2
      %true = arith.constant true
      %false = arith.constant false
      simulation.ref.store %pattern_lo to %a_lo : i65, !simulation.ref<i65>
      simulation.ref.store %pattern_hi to %a_hi : i63, !simulation.ref<i63>
      simulation.ref.store %pattern_lo to %b_lo : i65, !simulation.ref<i65>
      simulation.ref.store %pattern_hi to %b_hi : i63, !simulation.ref<i63>
      simulation.suspend.delay %two to ^one
    ^one:
      simulation.ref.store %true to %a : i1, !simulation.ref<i1>
      simulation.ref.store %true to %b : i1, !simulation.ref<i1>
      simulation.suspend.delay %two to ^zero
    ^zero:
      simulation.ref.store %false to %a : i1, !simulation.ref<i1>
      simulation.ref.store %false to %b : i1, !simulation.ref<i1>
      simulation.suspend.delay %two to ^again
    ^again:
      simulation.ref.store %true to %a : i1, !simulation.ref<i1>
      simulation.ref.store %true to %b : i1, !simulation.ref<i1>
      simulation.return
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 12 : i64} {
      %integer = simulation.context.storage %ctx[1] : !simulation.ref<i130>
      %packed = simulation.context.storage %ctx[4] : !simulation.ref<!packed>
      %base = arith.constant 340282366920938463555608327800315969537 : i130
      %both = arith.constant 1020847100762815390519251030811271495681 : i130
      %zero_time = simulation.time.constant 0
      %three = simulation.time.constant 3
      %two = simulation.time.constant 2
      %format = simulation.bytes.constant "integer lanes %0d %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %zero_time to ^startup
    ^startup:
      %a0 = simulation.ref.load %integer : !simulation.ref<i130> -> i130
      %p0 = simulation.ref.load %packed : !simulation.ref<!packed> -> !packed
      %b0 = simulation.packed.flatten %p0 : (!packed) -> i130
      %ok_a0 = arith.cmpi eq, %a0, %base : i130
      %ok_b0 = arith.cmpi eq, %b0, %base : i130
      simulation.display %ctx to %stdout(%format, %ok_a0, %ok_b0) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.suspend.delay %three to ^first
    ^first:
      %a1 = simulation.ref.load %integer : !simulation.ref<i130> -> i130
      %p1 = simulation.ref.load %packed : !simulation.ref<!packed> -> !packed
      %b1 = simulation.packed.flatten %p1 : (!packed) -> i130
      %ok_a1 = arith.cmpi eq, %a1, %both : i130
      %ok_b1 = arith.cmpi eq, %b1, %both : i130
      simulation.display %ctx to %stdout(%format, %ok_a1, %ok_b1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.suspend.delay %two to ^second
    ^second:
      %a2 = simulation.ref.load %integer : !simulation.ref<i130> -> i130
      %p2 = simulation.ref.load %packed : !simulation.ref<!packed> -> !packed
      %b2 = simulation.packed.flatten %p2 : (!packed) -> i130
      %ok_a2 = arith.cmpi eq, %a2, %base : i130
      %ok_b2 = arith.cmpi eq, %b2, %base : i130
      simulation.display %ctx to %stdout(%format, %ok_a2, %ok_b2) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.suspend.delay %two to ^third
    ^third:
      %a3 = simulation.ref.load %integer : !simulation.ref<i130> -> i130
      %p3 = simulation.ref.load %packed : !simulation.ref<!packed> -> !packed
      %b3 = simulation.packed.flatten %p3 : (!packed) -> i130
      %ok_a3 = arith.cmpi eq, %a3, %both : i130
      %ok_b3 = arith.cmpi eq, %b3, %both : i130
      simulation.display %ctx to %stdout(%format, %ok_a3, %ok_b3) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
