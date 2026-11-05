// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// A store marked as an NBA update performed early (as a clocked kernel's
// direct store is) publishes the wakes of its 2050 readers into the held
// ready set; the coordinator merges them once the NBA region's updates are
// complete (IEEE 1800-2023 4.5, 4.6(b), 4.7). With more than 2048 owners the
// ingress layout, which the held set shares, has a summary level: a merge
// visits only the leaves whose summary bits are set.

// 33 leaf words, the minimum cache and one summary word; every leaf can hold.
// CHECK: llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1() {{.*}}schedule.eval.nba_held_words = array<i32: 0, 1, 2, {{.*}}, 31, 32>} : !llvm.array<35 x i64>
// CHECK-LABEL: llvm.func {{.*}}@writer.__talos_eval_body_0(
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK: llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK: {{^  }}llvm.func
// The merge moves the summary word into the ingress summary and clears it,
// CHECK-LABEL: llvm.func internal @__talos_eval_nba_held_merge_v1()
// CHECK-NEXT: %[[HELD:[0-9]+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NEXT: %[[IN:[0-9]+]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-NEXT: %[[HS:[0-9]+]] = llvm.getelementptr %[[HELD]][272]
// CHECK-NEXT: %[[BITS:[0-9]+]] = llvm.load %[[HS]]
// CHECK:      ^bb1:
// CHECK-NEXT: %[[IS:[0-9]+]] = llvm.getelementptr %[[IN]][272]
// CHECK-NEXT: %[[HSV:[0-9]+]] = llvm.load %[[HS]]
// CHECK-NEXT: %[[ISV:[0-9]+]] = llvm.load %[[IS]]
// CHECK-NEXT: %[[SUM:[0-9]+]] = llvm.or %[[ISV]], %[[HSV]]
// CHECK-NEXT: llvm.store %[[SUM]], %[[IS]]
// CHECK-NEXT: llvm.mlir.constant(0 : i64)
// CHECK-NEXT: llvm.store %{{[0-9]+}}, %[[HS]]
// CHECK-NEXT: llvm.br ^bb2(%[[BITS]] : i64)
// then moves the one leaf each set bit names,
// CHECK:      ^bb2(%[[REST:[0-9]+]]: i64):
// CHECK:      ^bb3:
// CHECK-NEXT: %[[LEAF:[0-9]+]] = "llvm.intr.cttz"(%[[REST]])
// CHECK:      %[[HL:[0-9]+]] = llvm.getelementptr %[[HELD]][%[[LEAF]]]
// CHECK-NEXT: %[[IL:[0-9]+]] = llvm.getelementptr %[[IN]][%[[LEAF]]]
// CHECK-NEXT: %[[HV:[0-9]+]] = llvm.load %[[HL]]
// CHECK-NEXT: %[[IV:[0-9]+]] = llvm.load %[[IL]]
// CHECK-NEXT: %[[MV:[0-9]+]] = llvm.or %[[IV]], %[[HV]]
// CHECK-NEXT: llvm.store %[[MV]], %[[IL]]
// CHECK-NEXT: llvm.mlir.constant(0 : i64)
// CHECK-NEXT: llvm.store %{{[0-9]+}}, %[[HL]]
// and lowers the ingress minimum cache to the held one; the empty held set
// restarts past its 33 leaves.
// CHECK:      ^bb4:
// CHECK-NEXT: %[[HC:[0-9]+]] = llvm.getelementptr %[[HELD]][264]
// CHECK-NEXT: %[[IC:[0-9]+]] = llvm.getelementptr %[[IN]][264]
// CHECK-NEXT: %[[ICV:[0-9]+]] = llvm.load %[[IC]]
// CHECK-NEXT: %[[HCV:[0-9]+]] = llvm.load %[[HC]]
// CHECK-NEXT: %[[MIN:[0-9]+]] = llvm.intr.umin(%[[ICV]], %[[HCV]])
// CHECK-NEXT: llvm.store %[[MIN]], %[[IC]]
// CHECK-NEXT: %[[PAST:[0-9]+]] = llvm.mlir.constant(33 : i64)
// CHECK-NEXT: llvm.store %[[PAST]], %[[HC]]
// CHECK-NEXT: llvm.return
// Each merge point tests only the held summary word, then calls the merge.
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: %[[TH:[0-9]+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NEXT: %[[TS:[0-9]+]] = llvm.getelementptr %[[TH]][272]
// CHECK-NEXT: %[[TB:[0-9]+]] = llvm.load %[[TS]]
// CHECK-COUNT-5: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK-NOT: llvm.call @__talos_eval_nba_held_merge_v1()
// CHECK: {{^  }}llvm.func

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @held {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.writer"
    simulation.code_unit.decl 4 in 0 always hierarchy "t.reader#" {test.replicate = 2050 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design {test.replicate = 2050 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %d = simulation.context.storage %ctx[1] : !int
      %false = arith.constant false
      simulation.ref.store %false to %clk : i1, !clk
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %w = simulation.spawn @writer(%ctx, %clk, %d) : !simulation.context, !clk, !int -> !simulation.process
      %n = simulation.context.storage %ctx[2] {test.replicate = 2050 : i64, test.replicate_stride = {id = 1 : i64}} : !int
      %r = simulation.spawn @"reader#"(%ctx, %d, %n) {test.replicate = 2050 : i64} : !simulation.context, !int, !int -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clk -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %clk : i1, !clk
      cf.br ^wait
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %d : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %d {schedule.eval.nba_equivalent_store} : i32, !int
      cf.br ^wait
    }
    simulation.func @"reader#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.replicate_stride = {simulation.descriptor_id = 1 : i64}}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64, test.replicate = 2050 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %d to ^body {site = #schedule.continuation<id = 3>} : !int
    ^body:
      %v = simulation.ref.load %d : !int -> i32
      simulation.ref.store %v to %n : i32, !int
      cf.br ^wait
    }
  }
}

// -----

// 100 readers: two leaf words and the minimum cache, no summary level. The
// pending test ORs the listed leaves; the merge moves both and the caches.
// CHECK: llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1() {{.*}}schedule.eval.nba_held_words = array<i32: 0, 1>} : !llvm.array<3 x i64>
// CHECK-LABEL: llvm.func internal @__talos_eval_nba_held_merge_v1()
// CHECK-NEXT: %[[FHELD:[0-9]+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NEXT: %[[FIN:[0-9]+]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-NEXT: %[[W0:[0-9]+]] = llvm.load %[[FHELD]]
// CHECK-NEXT: %[[I0:[0-9]+]] = llvm.load %[[FIN]]
// CHECK-NEXT: %[[M0:[0-9]+]] = llvm.or %[[I0]], %[[W0]]
// CHECK-NEXT: llvm.store %[[M0]], %[[FIN]]
// CHECK-NEXT: llvm.mlir.constant(0 : i64)
// CHECK-NEXT: llvm.store %{{[0-9]+}}, %[[FHELD]]
// CHECK-NEXT: %[[H1:[0-9]+]] = llvm.getelementptr %[[FHELD]][8]
// CHECK-NEXT: %[[J1:[0-9]+]] = llvm.getelementptr %[[FIN]][8]
// CHECK-NEXT: %[[W1:[0-9]+]] = llvm.load %[[H1]]
// CHECK-NEXT: %[[I1:[0-9]+]] = llvm.load %[[J1]]
// CHECK-NEXT: %[[M1:[0-9]+]] = llvm.or %[[I1]], %[[W1]]
// CHECK-NEXT: llvm.store %[[M1]], %[[J1]]
// CHECK-NEXT: llvm.mlir.constant(0 : i64)
// CHECK-NEXT: llvm.store %{{[0-9]+}}, %[[H1]]
// CHECK-NEXT: %[[HC:[0-9]+]] = llvm.getelementptr %[[FHELD]][16]
// CHECK-NEXT: %[[IC:[0-9]+]] = llvm.getelementptr %[[FIN]][16]
// CHECK-NEXT: %[[ICV:[0-9]+]] = llvm.load %[[IC]]
// CHECK-NEXT: %[[HCV:[0-9]+]] = llvm.load %[[HC]]
// CHECK-NEXT: %[[MIN:[0-9]+]] = llvm.intr.umin(%[[ICV]], %[[HCV]])
// CHECK-NEXT: llvm.store %[[MIN]], %[[IC]]
// CHECK-NEXT: %[[PAST:[0-9]+]] = llvm.mlir.constant(2 : i64)
// CHECK-NEXT: llvm.store %[[PAST]], %[[HC]]
// CHECK-NEXT: llvm.return

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @held_flat {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.writer"
    simulation.code_unit.decl 4 in 0 always hierarchy "t.reader#" {test.replicate = 100 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design {test.replicate = 100 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %d = simulation.context.storage %ctx[1] : !int
      %false = arith.constant false
      simulation.ref.store %false to %clk : i1, !clk
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %w = simulation.spawn @writer(%ctx, %clk, %d) : !simulation.context, !clk, !int -> !simulation.process
      %n = simulation.context.storage %ctx[2] {test.replicate = 100 : i64, test.replicate_stride = {id = 1 : i64}} : !int
      %r = simulation.spawn @"reader#"(%ctx, %d, %n) {test.replicate = 100 : i64} : !simulation.context, !int, !int -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clk -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %clk : i1, !clk
      cf.br ^wait
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %d : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %d {schedule.eval.nba_equivalent_store} : i32, !int
      cf.br ^wait
    }
    simulation.func @"reader#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.replicate_stride = {simulation.descriptor_id = 1 : i64}}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64, test.replicate = 100 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %d to ^body {site = #schedule.continuation<id = 3>} : !int
    ^body:
      %v = simulation.ref.load %d : !int -> i32
      simulation.ref.store %v to %n : i32, !int
      cf.br ^wait
    }
  }
}
