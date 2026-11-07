// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FUSED --implicit-check-not='simulation.spawn @a0_' --implicit-check-not='simulation.spawn @a1_' --implicit-check-not='simulation.spawn @b0_' --implicit-check-not='simulation.spawn @b1_' < %t.sim.mlir
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,test-talos-repeatable-activations))' -o /dev/null 2>&1 | FileCheck %s --check-prefix=STRICT
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 4.3/9.4.2/10.4.1: an implicit packed-cell hold and an
// explicit self-assignment preserve the same value and change-event sequence.
// Preserve the conditional store and its exact low-byte target. A transport
// comes first in each cohort; only that stateless transport is split. Each
// holding process stays whole, and the kernel must retain the always_comb
// startup phase (9.2.2.2), after Initial changes enable/data. Otherwise it
// captures the pre-initial value instead of retaining startup X. Later test
// disabled data changes, nonzero neighboring lanes, and an enable pulse across
// #0 (4.4.2.2/4.4.2.3) that must capture before the pulse is deasserted.
// FUSED-DAG: simulation.func private @__talos_region_kernel_{{[0-9]+}}_0({{.*}}attributes {code_unit_id = 2 : i64, {{.*}}entry_kind = 4 : i32
// FUSED-DAG: simulation.func private @__talos_region_kernel_{{[0-9]+}}_0({{.*}}attributes {code_unit_id = 4 : i64, {{.*}}entry_kind = 4 : i32
// STRICT-DAG: repeatable @b0_implicit = 0
// STRICT-DAG: repeatable @b1_explicit = 0
// FUSED-DAG: simulation.func @z0_high({{.*}}effect = watch, resource = storage, target = descriptor, descriptor = 4, formal = 0, low = 8, width = 8, dynamic = false
// FUSED-DAG: simulation.func @z1_high({{.*}}effect = watch, resource = storage, target = descriptor, descriptor = 7, formal = 0, low = 8, width = 8, dynamic = false
// OUTPUT-COUNT-4: {{^}}holds 1 1 1 1{{$}}

!word = !simulation.logic<8>
!wide = !simulation.logic<16>
!ref = !simulation.ref<!word>
!wide_ref = !simulation.ref<!wide>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @implicit_and_explicit_holds {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !word design
    simulation.storage.decl 2 in 0 : !word design
    simulation.storage.decl 3 in 0 : !word design
    simulation.storage.decl 4 in 0 : !wide design
    simulation.storage.decl 5 in 0 : !word design
    simulation.storage.decl 6 in 0 : !word design
    simulation.storage.decl 7 in 0 : !wide design
    simulation.storage.decl 8 in 0 : !word design
    simulation.storage.decl 9 in 0 : !word design
    simulation.storage.decl 10 in 0 : !word design
    simulation.storage.decl 11 in 0 : !word design
    simulation.code_unit.decl 1 in 0 continuous hierarchy "a0_transport"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b0_implicit"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "a1_transport"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "b1_explicit"
    simulation.code_unit.decl 5 in 0 initial hierarchy "drive"
    simulation.code_unit.decl 6 in 0 initial hierarchy "check"
    simulation.code_unit.decl 7 in 0 continuous hierarchy "z0_high"
    simulation.code_unit.decl 8 in 0 continuous hierarchy "z1_high"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %enable = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %data = simulation.context.storage %ctx[1] : !ref
      %true = arith.constant true
      %seven = simulation.logic.constant 7 : i8, 0 : i8 : !word
      simulation.ref.store %true to %enable : i1, !simulation.ref<i1>
      simulation.ref.store %seven to %data : !word, !ref
      %p0 = simulation.spawn @a0_transport(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @b0_implicit(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @a1_transport(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @b1_explicit(%ctx) : !simulation.context -> !simulation.process
      %p4 = simulation.spawn @z0_high(%ctx) : !simulation.context -> !simulation.process
      %p5 = simulation.spawn @z1_high(%ctx) : !simulation.context -> !simulation.process
      %p6 = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      %p7 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @a0_transport(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[1] : !ref
      %request = simulation.context.storage %ctx[2] : !ref
      %response = simulation.context.storage %ctx[3] : !ref
      %result = simulation.context.storage %ctx[10] : !ref
      cf.br ^body
    ^body:
      %old_response = simulation.ref.load %response : !ref -> !word
      simulation.ref.store %old_response to %result : !word, !ref
      %payload = simulation.ref.load %input : !ref -> !word
      simulation.ref.store %payload to %request : !word, !ref
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @b0_implicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %enable = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %request = simulation.context.storage %ctx[2] : !ref
      %response = simulation.context.storage %ctx[3] : !ref
      %whole = simulation.context.storage %ctx[4] : !wide_ref
      %state = simulation.ref.extract %whole from 0 : !wide_ref -> !ref
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !word
      cf.br ^body
    ^body:
      %payload = simulation.ref.load %request : !ref -> !word
      %incoming = simulation.logic.binary add %payload, %one : !word
      %flag = simulation.ref.load %enable : !simulation.ref<i1> -> i1
      cf.cond_br %flag, ^capture, ^request
    ^capture:
      simulation.ref.store %incoming to %state : !word, !ref
      cf.br ^request
    ^request:
      simulation.ref.store %incoming to %response : !word, !ref
      simulation.suspend.any %enable, %request edges [0, 0] to ^body : !simulation.ref<i1>, !ref
    }
    simulation.func @z0_high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 7 : i64} {
      %whole = simulation.context.storage %ctx[4] : !wide_ref
      %input = simulation.ref.extract %whole from 8 : !wide_ref -> !ref
      %output = simulation.context.storage %ctx[8] : !ref
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !ref -> !word
      simulation.ref.store %value to %output : !word, !ref
      simulation.suspend.change %input to ^body : !ref
    }
    simulation.func @a1_transport(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[1] : !ref
      %request = simulation.context.storage %ctx[5] : !ref
      %response = simulation.context.storage %ctx[6] : !ref
      %result = simulation.context.storage %ctx[11] : !ref
      cf.br ^body
    ^body:
      %old_response = simulation.ref.load %response : !ref -> !word
      simulation.ref.store %old_response to %result : !word, !ref
      %payload = simulation.ref.load %input : !ref -> !word
      simulation.ref.store %payload to %request : !word, !ref
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @b1_explicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %enable = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %request = simulation.context.storage %ctx[5] : !ref
      %response = simulation.context.storage %ctx[6] : !ref
      %whole = simulation.context.storage %ctx[7] : !wide_ref
      %state = simulation.ref.extract %whole from 0 : !wide_ref -> !ref
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !word
      cf.br ^body
    ^body:
      %payload = simulation.ref.load %request : !ref -> !word
      %incoming = simulation.logic.binary add %payload, %one : !word
      %flag = simulation.ref.load %enable : !simulation.ref<i1> -> i1
      cf.cond_br %flag, ^capture, ^hold
    ^capture:
      simulation.ref.store %incoming to %state : !word, !ref
      cf.br ^request
    ^hold:
      %old = simulation.ref.load %state : !ref -> !word
      simulation.ref.store %old to %state : !word, !ref
      cf.br ^request
    ^request:
      simulation.ref.store %incoming to %response : !word, !ref
      simulation.suspend.any %enable, %request edges [0, 0] to ^body : !simulation.ref<i1>, !ref
    }
    simulation.func @z1_high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 8 : i64} {
      %whole = simulation.context.storage %ctx[7] : !wide_ref
      %input = simulation.ref.extract %whole from 8 : !wide_ref -> !ref
      %output = simulation.context.storage %ctx[9] : !ref
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !ref -> !word
      simulation.ref.store %value to %output : !word, !ref
      simulation.suspend.change %input to ^body : !ref
    }
    simulation.func @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %enable = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %data = simulation.context.storage %ctx[1] : !ref
      %qi = simulation.context.storage %ctx[4] : !wide_ref
      %qe = simulation.context.storage %ctx[7] : !wide_ref
      %hi = simulation.ref.extract %qi from 8 : !wide_ref -> !ref
      %he = simulation.ref.extract %qe from 8 : !wide_ref -> !ref
      %true = arith.constant true
      %false = arith.constant false
      %nine = simulation.logic.constant 9 : i8, 0 : i8 : !word
      %thirty = simulation.logic.constant 30 : i8, 0 : i8 : !word
      %forty = simulation.logic.constant 40 : i8, 0 : i8 : !word
      %a5 = simulation.logic.constant 165 : i8, 0 : i8 : !word
      %fivea = simulation.logic.constant 90 : i8, 0 : i8 : !word
      %two = simulation.time.constant 2
      %zero_time = simulation.time.constant 0
      simulation.ref.store %false to %enable : i1, !simulation.ref<i1>
      simulation.ref.store %nine to %data : !word, !ref
      simulation.ref.store %a5 to %hi : !word, !ref
      simulation.ref.store %a5 to %he : !word, !ref
      simulation.suspend.delay %two to ^capture
    ^capture:
      simulation.ref.store %true to %enable : i1, !simulation.ref<i1>
      simulation.suspend.delay %two to ^disabled
    ^disabled:
      simulation.ref.store %false to %enable : i1, !simulation.ref<i1>
      simulation.ref.store %thirty to %data : !word, !ref
      simulation.ref.store %fivea to %hi : !word, !ref
      simulation.ref.store %fivea to %he : !word, !ref
      simulation.suspend.delay %two to ^pulse
    ^pulse:
      simulation.ref.store %forty to %data : !word, !ref
      simulation.ref.store %true to %enable : i1, !simulation.ref<i1>
      simulation.suspend.delay %zero_time to ^deassert
    ^deassert:
      simulation.ref.store %false to %enable : i1, !simulation.ref<i1>
      simulation.return
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %qi = simulation.context.storage %ctx[4] : !wide_ref
      %qe = simulation.context.storage %ctx[7] : !wide_ref
      %ri = simulation.context.storage %ctx[10] : !ref
      %re = simulation.context.storage %ctx[11] : !ref
      %ten = simulation.logic.constant 10 : i8, 0 : i8 : !word
      %thirty_one = simulation.logic.constant 31 : i8, 0 : i8 : !word
      %forty_one = simulation.logic.constant 41 : i8, 0 : i8 : !word
      %hi = simulation.context.storage %ctx[8] : !ref
      %he = simulation.context.storage %ctx[9] : !ref
      %startup = simulation.logic.constant 42240 : i16, 255 : i16 : !wide
      %captured = simulation.logic.constant 42250 : i16, 0 : i16 : !wide
      %held = simulation.logic.constant 23050 : i16, 0 : i16 : !wide
      %pulsed = simulation.logic.constant 23081 : i16, 0 : i16 : !wide
      %a5 = simulation.logic.constant 165 : i8, 0 : i8 : !word
      %fivea = simulation.logic.constant 90 : i8, 0 : i8 : !word
      %zero_time = simulation.time.constant 0
      %three = simulation.time.constant 3
      %two = simulation.time.constant 2
      %format = simulation.bytes.constant "holds %0d %0d %0d %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %zero_time to ^startup
    ^startup:
      %qi0 = simulation.ref.load %qi : !wide_ref -> !wide
      %qe0 = simulation.ref.load %qe : !wide_ref -> !wide
      %hi0 = simulation.ref.load %hi : !ref -> !word
      %he0 = simulation.ref.load %he : !ref -> !word
      %result_i0 = simulation.ref.load %ri : !ref -> !word
      %result_e0 = simulation.ref.load %re : !ref -> !word
      %ok_ri0 = simulation.logic.compare case_eq %result_i0, %ten : (!word, !word) -> i1
      %ok_re0 = simulation.logic.compare case_eq %result_e0, %ten : (!word, !word) -> i1
      %ok_i0 = simulation.logic.compare case_eq %qi0, %startup : (!wide, !wide) -> i1
      %ok_e0 = simulation.logic.compare case_eq %qe0, %startup : (!wide, !wide) -> i1
      %ok_hi0 = simulation.logic.compare case_eq %hi0, %a5 : (!word, !word) -> i1
      %ok_he0 = simulation.logic.compare case_eq %he0, %a5 : (!word, !word) -> i1
      %both_i0 = arith.andi %ok_i0, %ok_ri0 : i1
      %both_e0 = arith.andi %ok_e0, %ok_re0 : i1
      simulation.display %ctx to %stdout(%format, %both_i0, %both_e0, %ok_hi0, %ok_he0) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1
      simulation.suspend.delay %three to ^captured
    ^captured:
      %qi1 = simulation.ref.load %qi : !wide_ref -> !wide
      %qe1 = simulation.ref.load %qe : !wide_ref -> !wide
      %hi1 = simulation.ref.load %hi : !ref -> !word
      %he1 = simulation.ref.load %he : !ref -> !word
      %result_i1 = simulation.ref.load %ri : !ref -> !word
      %result_e1 = simulation.ref.load %re : !ref -> !word
      %ok_ri1 = simulation.logic.compare case_eq %result_i1, %ten : (!word, !word) -> i1
      %ok_re1 = simulation.logic.compare case_eq %result_e1, %ten : (!word, !word) -> i1
      %ok_i1 = simulation.logic.compare case_eq %qi1, %captured : (!wide, !wide) -> i1
      %ok_e1 = simulation.logic.compare case_eq %qe1, %captured : (!wide, !wide) -> i1
      %ok_hi1 = simulation.logic.compare case_eq %hi1, %a5 : (!word, !word) -> i1
      %ok_he1 = simulation.logic.compare case_eq %he1, %a5 : (!word, !word) -> i1
      %both_i1 = arith.andi %ok_i1, %ok_ri1 : i1
      %both_e1 = arith.andi %ok_e1, %ok_re1 : i1
      simulation.display %ctx to %stdout(%format, %both_i1, %both_e1, %ok_hi1, %ok_he1) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1
      simulation.suspend.delay %two to ^held
    ^held:
      %qi2 = simulation.ref.load %qi : !wide_ref -> !wide
      %qe2 = simulation.ref.load %qe : !wide_ref -> !wide
      %hi2 = simulation.ref.load %hi : !ref -> !word
      %he2 = simulation.ref.load %he : !ref -> !word
      %result_i2 = simulation.ref.load %ri : !ref -> !word
      %result_e2 = simulation.ref.load %re : !ref -> !word
      %ok_ri2 = simulation.logic.compare case_eq %result_i2, %thirty_one : (!word, !word) -> i1
      %ok_re2 = simulation.logic.compare case_eq %result_e2, %thirty_one : (!word, !word) -> i1
      %ok_i2 = simulation.logic.compare case_eq %qi2, %held : (!wide, !wide) -> i1
      %ok_e2 = simulation.logic.compare case_eq %qe2, %held : (!wide, !wide) -> i1
      %ok_hi2 = simulation.logic.compare case_eq %hi2, %fivea : (!word, !word) -> i1
      %ok_he2 = simulation.logic.compare case_eq %he2, %fivea : (!word, !word) -> i1
      %both_i2 = arith.andi %ok_i2, %ok_ri2 : i1
      %both_e2 = arith.andi %ok_e2, %ok_re2 : i1
      simulation.display %ctx to %stdout(%format, %both_i2, %both_e2, %ok_hi2, %ok_he2) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1
      simulation.suspend.delay %two to ^pulsed
    ^pulsed:
      %qi3 = simulation.ref.load %qi : !wide_ref -> !wide
      %qe3 = simulation.ref.load %qe : !wide_ref -> !wide
      %hi3 = simulation.ref.load %hi : !ref -> !word
      %he3 = simulation.ref.load %he : !ref -> !word
      %result_i3 = simulation.ref.load %ri : !ref -> !word
      %result_e3 = simulation.ref.load %re : !ref -> !word
      %ok_ri3 = simulation.logic.compare case_eq %result_i3, %forty_one : (!word, !word) -> i1
      %ok_re3 = simulation.logic.compare case_eq %result_e3, %forty_one : (!word, !word) -> i1
      %ok_i3 = simulation.logic.compare case_eq %qi3, %pulsed : (!wide, !wide) -> i1
      %ok_e3 = simulation.logic.compare case_eq %qe3, %pulsed : (!wide, !wide) -> i1
      %ok_hi3 = simulation.logic.compare case_eq %hi3, %fivea : (!word, !word) -> i1
      %ok_he3 = simulation.logic.compare case_eq %he3, %fivea : (!word, !word) -> i1
      %both_i3 = arith.andi %ok_i3, %ok_ri3 : i1
      %both_e3 = arith.andi %ok_e3, %ok_re3 : i1
      simulation.display %ctx to %stdout(%format, %both_i3, %both_e3, %ok_hi3, %ok_he3) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
