// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FORWARD --implicit-check-not='simulation.spawn @low' --implicit-check-not='simulation.spawn @high' < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 6.6.1/11.4.12: a disjoint strong partition preserves
// packed bit positions. Join unequal pieces across the native word boundary,
// and read a window crossing the piece boundary at bit66. Check entire values
// as well as that window after startup and after changes to both sources.
// FORWARD-LABEL: simulation.func private @reader(
// FORWARD: simulation.suspend.any
// OUTPUT-COUNT-3: {{^}}integer pieces 1 1{{$}}

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @integer_pieces_runtime {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.code_unit.decl 6 in 0 initial hierarchy "check"
    simulation.storage.decl 0 in 0 : i66 design
    simulation.storage.decl 1 in 0 : i130 design
    simulation.storage.decl 2 in 0 : i64 design
    simulation.storage.decl 3 in 0 : i4 design
    simulation.net.decl 0 in 0 : i130 design
    simulation.driver.decl 0 in 0 drives 0 : i130 design {driven_low = 0 : i64, driven_width = 66 : i64}
    simulation.driver.decl 1 in 0 drives 0 : i130 design {driven_low = 66 : i64, driven_width = 64 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i66>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<i64>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<i130>
      %c = simulation.context.storage %ctx[3] : !simulation.ref<i4>
      %n = simulation.context.net %ctx[0] : !simulation.net<i130>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<i130>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<i130>
      %p0 = simulation.spawn @low(%ctx, %a, %d0) : !simulation.context, !simulation.ref<i66>, !simulation.driver<i130> -> !simulation.process
      %p1 = simulation.spawn @high(%ctx, %b, %d1) : !simulation.context, !simulation.ref<i64>, !simulation.driver<i130> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %n, %d, %c) : !simulation.context, !simulation.net<i130>, !simulation.ref<i130>, !simulation.ref<i4> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %a, %b) : !simulation.context, !simulation.ref<i66>, !simulation.ref<i64> -> !simulation.process
      %p4 = simulation.spawn @check(%ctx, %d, %c) : !simulation.context, !simulation.ref<i130>, !simulation.ref<i4> -> !simulation.process
      simulation.return
    }
    simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i66> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<i130> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i66> -> i66
      %part = simulation.driver.extract %drv from 0 : !simulation.driver<i130> -> !simulation.driver<i66>
      simulation.driver.drive %part = %v : !simulation.driver<i66>, i66
      simulation.suspend.change %src to ^body : !simulation.ref<i66>
    }
    simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i64> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<i130> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i64> -> i64
      %part = simulation.driver.extract %drv from 66 : !simulation.driver<i130> -> !simulation.driver<i64>
      simulation.driver.drive %part = %v : !simulation.driver<i64>, i64
      simulation.suspend.change %src to ^body : !simulation.ref<i64>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<i130> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<i130> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %clip: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %window = simulation.net.extract %in from 64 : !simulation.net<i130> -> !simulation.net<i4>
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<i130> -> i130
      %c = simulation.net.read %window : !simulation.net<i4> -> i4
      simulation.ref.store %v to %out : i130, !simulation.ref<i130>
      simulation.ref.store %c to %clip : i4, !simulation.ref<i4>
      simulation.suspend.change %in to ^body {schedule.procedural_event_wait} : !simulation.net<i130>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<i66> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<i64> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %two = simulation.time.constant 2
      %a0 = arith.constant 55340232221128654849 : i66
      %b0 = arith.constant 13835058055282163715 : i64
      %a1 = arith.constant 36893488147419103234 : i66
      %b1 = arith.constant 9223372036854775812 : i64
      %a2 = arith.constant 18446744073709551620 : i66
      %b2 = arith.constant 4611686018427387906 : i64
      simulation.ref.store %a0 to %a : i66, !simulation.ref<i66>
      simulation.ref.store %b0 to %b : i64, !simulation.ref<i64>
      simulation.suspend.delay %two to ^first
    ^first:
      simulation.ref.store %a1 to %a : i66, !simulation.ref<i66>
      simulation.ref.store %b1 to %b : i64, !simulation.ref<i64>
      simulation.suspend.delay %two to ^second
    ^second:
      simulation.ref.store %a2 to %a : i66, !simulation.ref<i66>
      simulation.ref.store %b2 to %b : i64, !simulation.ref<i64>
      simulation.return
    }
    simulation.func private @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %whole: !simulation.ref<i130> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %clip: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %one = simulation.time.constant 1
      %two = simulation.time.constant 2
      %expect0 = arith.constant 1020847100762815390666824983400947908609 : i130
      %expect1 = arith.constant 680564733841876927258790608190308352002 : i130
      %expect2 = arith.constant 340282366920938463629395304095154176004 : i130
      %clip0 = arith.constant 15 : i4
      %clip1 = arith.constant 2 : i4
      %clip2 = arith.constant 9 : i4
      %format = simulation.bytes.constant "integer pieces %0d %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %one to ^startup
    ^startup:
      %v0 = simulation.ref.load %whole : !simulation.ref<i130> -> i130
      %c0 = simulation.ref.load %clip : !simulation.ref<i4> -> i4
      %ok_v0 = arith.cmpi eq, %v0, %expect0 : i130
      %ok_c0 = arith.cmpi eq, %c0, %clip0 : i4
      simulation.display %ctx to %stdout(%format, %ok_v0, %ok_c0) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.suspend.delay %two to ^first
    ^first:
      %v1 = simulation.ref.load %whole : !simulation.ref<i130> -> i130
      %c1 = simulation.ref.load %clip : !simulation.ref<i4> -> i4
      %ok_v1 = arith.cmpi eq, %v1, %expect1 : i130
      %ok_c1 = arith.cmpi eq, %c1, %clip1 : i4
      simulation.display %ctx to %stdout(%format, %ok_v1, %ok_c1) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.suspend.delay %two to ^second
    ^second:
      %v2 = simulation.ref.load %whole : !simulation.ref<i130> -> i130
      %c2 = simulation.ref.load %clip : !simulation.ref<i4> -> i4
      %ok_v2 = arith.cmpi eq, %v2, %expect2 : i130
      %ok_c2 = arith.cmpi eq, %c2, %clip2 : i4
      simulation.display %ctx to %stdout(%format, %ok_v2, %ok_c2) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
