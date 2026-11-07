// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true},talos-sim-propagate-initialized-storage{vpi=off},symbol-dce,simulation.func(canonicalize,cse)))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FORWARD --implicit-check-not='simulation.spawn @report' < %t.sim.mlir
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT --implicit-check-not='unexpected final failure'
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT --implicit-check-not='unexpected final failure'

// IEEE 1800-2023 16.4-16.4.2: initial a=p=0 can cause a transient
// Active failure of p!=a before p=!a starts. Subsequent input changes can
// also enter the monitor before its producer, through Inactive, NBA and
// Reactive writes. Those failures must flush before Postponed;
// the independent p==a monitor must still report once in each time slot.
// FORWARD-LABEL: simulation.func private @live(
// FORWARD: simulation.assert.deferred_enqueue 2
// FORWARD: simulation.spawn @live_report
// OUTPUT-COUNT-3: {{^}}live final failure{{$}}

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @settled_final {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "live"
    simulation.code_unit.decl 6 in 0 fork hierarchy "live_report"
    simulation.code_unit.decl 7 in 0 initial hierarchy "drive"
    simulation.code_unit.decl 8 in 0 initial hierarchy "finish"
    simulation.code_unit.decl 9 in 0 initial hierarchy "reactive_drive"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @live(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      %p4 = simulation.spawn @finish(%ctx) : !simulation.context -> !simulation.process
      %p5 = simulation.spawn @reactive_drive(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %true = arith.constant true
      cf.br ^body
    ^body:
      %v = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %not = arith.xori %v, %true : i1
      simulation.ref.store %not to %p : i1, !simulation.ref<i1>
      simulation.suspend.change %a to ^body : !simulation.ref<i1>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %pv = simulation.ref.load %p : !simulation.ref<i1> -> i1
      %ok = arith.cmpi ne, %pv, %av : i1
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i1>, !simulation.ref<i1>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @live(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %epoch = simulation.context.storage %ctx[3] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %pv = simulation.ref.load %p : !simulation.ref<i1> -> i1
      %ok = arith.cmpi eq, %pv, %av : i1
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 2 {simulation.deferred_epoch_storage = 3 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @live_report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i1>, !simulation.ref<i1>
    }
    simulation.func private @live_report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 6 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[3] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "live final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %zero = simulation.time.constant 0
      %two = simulation.time.constant 2
      %true = arith.constant true
      %false = arith.constant false
      simulation.suspend.delay %zero to ^inactive
    ^inactive:
      simulation.ref.store %true to %a : i1, !simulation.ref<i1>
      simulation.suspend.delay %two to ^nba
    ^nba:
      simulation.nba.enqueue %false to %a : (i1, !simulation.ref<i1>) -> ()
      simulation.return
    }
    simulation.func private @reactive_drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 9 : i64, domain = 1 : i32, home_region = 10 : i32} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %four = simulation.time.constant 4
      simulation.suspend.delay %four to ^reactive
    ^reactive:
      %true = arith.constant true
      simulation.ref.store %true to %a : i1, !simulation.ref<i1>
      simulation.return
    }
    simulation.func private @finish(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 8 : i64} {
      %five = simulation.time.constant 5
      simulation.suspend.delay %five to ^end
    ^end:
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
