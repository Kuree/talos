// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=full},talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph{vpi=full},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),talos-sim-materialize-dpi-exports,encode-talos-sim-to-bytecode{vpi=full},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.mlir 2> %t.log
// RUN: FileCheck %s --check-prefix=PLAN < %t.log && FileCheck %s --check-prefix=IR < %t.mlir

// Only constant queries can use the shared calendar with DPI exports. A read
// of live design state and an effectful export keep the conservative calendar.
// Context imports and live VPI guards are unchanged (IEEE 1800-2023 35.5.3).
// PLAN: dpi-exports=1 constant-query-exports=1 coverage=0 eligible=1
// PLAN: dpi-exports=1 constant-query-exports=0 coverage=0 eligible=0
// PLAN: dpi-exports=1 constant-query-exports=0 coverage=0 eligible=0
// IR: module attributes {{.*}}schedule.eval.runtime_calendar
// IR: llvm.mlir.global internal constant @__talos_aot_schedule_plan_v1
// Constant-query (32768), shared-periodic (8192), and runtime-calendar (4096)
// are present together with this fixture's ordinary island capabilities.
// IR: %[[FLAGS:[0-9]+]] = llvm.mlir.constant(48478 : i32)
// IR-NEXT: llvm.insertvalue %[[FLAGS]], %{{[0-9]+}}[5]

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, dpi.has_exports, native.debug_timing} {
  simulation.design @held_calendar {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.kernel"
    simulation.code_unit.decl 4 in 0 initial hierarchy "t.finisher"
    simulation.code_unit.decl 5 in 0 always hierarchy "t.reader"
    simulation.code_unit.decl 6 in 0 function hierarchy "t.query"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %q = simulation.context.storage %ctx[1] : !int
      %n = simulation.context.storage %ctx[2] : !int
      %false = arith.constant false
      %zero = arith.constant 0 : i32
      simulation.ref.store %false to %clk : i1, !clk
      simulation.ref.store %zero to %q : i32, !int
      simulation.ref.store %zero to %n : i32, !int
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %k = simulation.spawn @kernel(%ctx, %clk, %q) : !simulation.context, !clk, !int -> !simulation.process
      %f = simulation.spawn @finisher(%ctx, %clk, %n) : !simulation.context, !clk, !int -> !simulation.process
      %r = simulation.context.storage %ctx[3] : !int
      %rd = simulation.spawn @reader(%ctx, %q, %r) : !simulation.context, !int, !int -> !simulation.process
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
    // `always @(posedge clk) q <= q + 1` as a deferred clocked kernel.
    simulation.func @kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 3 : i32, schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %q {schedule.eval.nba_equivalent_store} : i32, !int
      cf.br ^wait
    }
    // `always @(q) r = q`, a generated owner the store wakes.
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %q to ^body {site = #schedule.continuation<id = 4>} : !int
    ^body:
      %v = simulation.ref.load %q : !int -> i32
      simulation.ref.store %v to %r : i32, !int
      cf.br ^wait
    }
    // `always @(posedge clk) if (++n == 3) $finish` stays in Active.
    simulation.func @finisher(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 3>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %n : i32, !int
      %three = arith.constant 3 : i32
      %done = arith.cmpi eq, %new, %three : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
    simulation.func @query_impl(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64, dpi.export, dpi.c_identifier = "query", dpi.export_id = 42 : i32, dpi.scope_id = 0 : i64, dpi.logical_inputs = 0 : i32, dpi.abi_signature = [#dpi.abi<kind = int, direction = result, width = 32, fourState = false, isSigned = true>]} {
      %period = arith.constant 10 : i32
      simulation.return %period : i32
    }
  }
}

// -----

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, dpi.has_exports, native.debug_timing} {
  simulation.design @held_calendar {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.kernel"
    simulation.code_unit.decl 4 in 0 initial hierarchy "t.finisher"
    simulation.code_unit.decl 5 in 0 always hierarchy "t.reader"
    simulation.code_unit.decl 6 in 0 function hierarchy "t.query"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %q = simulation.context.storage %ctx[1] : !int
      %n = simulation.context.storage %ctx[2] : !int
      %false = arith.constant false
      %zero = arith.constant 0 : i32
      simulation.ref.store %false to %clk : i1, !clk
      simulation.ref.store %zero to %q : i32, !int
      simulation.ref.store %zero to %n : i32, !int
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %k = simulation.spawn @kernel(%ctx, %clk, %q) : !simulation.context, !clk, !int -> !simulation.process
      %f = simulation.spawn @finisher(%ctx, %clk, %n) : !simulation.context, !clk, !int -> !simulation.process
      %r = simulation.context.storage %ctx[3] : !int
      %rd = simulation.spawn @reader(%ctx, %q, %r) : !simulation.context, !int, !int -> !simulation.process
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
    // `always @(posedge clk) q <= q + 1` as a deferred clocked kernel.
    simulation.func @kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 3 : i32, schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %q {schedule.eval.nba_equivalent_store} : i32, !int
      cf.br ^wait
    }
    // `always @(q) r = q`, a generated owner the store wakes.
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %q to ^body {site = #schedule.continuation<id = 4>} : !int
    ^body:
      %v = simulation.ref.load %q : !int -> i32
      simulation.ref.store %v to %r : i32, !int
      cf.br ^wait
    }
    // `always @(posedge clk) if (++n == 3) $finish` stays in Active.
    simulation.func @finisher(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 3>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %n : i32, !int
      %three = arith.constant 3 : i32
      %done = arith.cmpi eq, %new, %three : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
    simulation.func @query_impl(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64, dpi.export, dpi.c_identifier = "query", dpi.export_id = 42 : i32, dpi.scope_id = 0 : i64, dpi.logical_inputs = 0 : i32, dpi.abi_signature = [#dpi.abi<kind = int, direction = result, width = 32, fourState = false, isSigned = true>]} {
      %ref = simulation.context.storage %ctx[1] : !int
      %period = simulation.ref.load %ref : !int -> i32
      simulation.return %period : i32
    }
  }
}

// -----

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, dpi.has_exports, native.debug_timing} {
  simulation.design @held_calendar {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.kernel"
    simulation.code_unit.decl 4 in 0 initial hierarchy "t.finisher"
    simulation.code_unit.decl 5 in 0 always hierarchy "t.reader"
    simulation.code_unit.decl 6 in 0 function hierarchy "t.query"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.storage.decl 3 in 0 : i32 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %q = simulation.context.storage %ctx[1] : !int
      %n = simulation.context.storage %ctx[2] : !int
      %false = arith.constant false
      %zero = arith.constant 0 : i32
      simulation.ref.store %false to %clk : i1, !clk
      simulation.ref.store %zero to %q : i32, !int
      simulation.ref.store %zero to %n : i32, !int
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %k = simulation.spawn @kernel(%ctx, %clk, %q) : !simulation.context, !clk, !int -> !simulation.process
      %f = simulation.spawn @finisher(%ctx, %clk, %n) : !simulation.context, !clk, !int -> !simulation.process
      %r = simulation.context.storage %ctx[3] : !int
      %rd = simulation.spawn @reader(%ctx, %q, %r) : !simulation.context, !int, !int -> !simulation.process
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
    // `always @(posedge clk) q <= q + 1` as a deferred clocked kernel.
    simulation.func @kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 3 : i32, schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %q {schedule.eval.nba_equivalent_store} : i32, !int
      cf.br ^wait
    }
    // `always @(q) r = q`, a generated owner the store wakes.
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %q to ^body {site = #schedule.continuation<id = 4>} : !int
    ^body:
      %v = simulation.ref.load %q : !int -> i32
      simulation.ref.store %v to %r : i32, !int
      cf.br ^wait
    }
    // `always @(posedge clk) if (++n == 3) $finish` stays in Active.
    simulation.func @finisher(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 3>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %n : i32, !int
      %three = arith.constant 3 : i32
      %done = arith.cmpi eq, %new, %three : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
    simulation.func @query_impl(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64, dpi.export, dpi.c_identifier = "query", dpi.export_id = 42 : i32, dpi.scope_id = 0 : i64, dpi.logical_inputs = 0 : i32, dpi.abi_signature = [#dpi.abi<kind = int, direction = result, width = 32, fourState = false, isSigned = true>]} {
      %period = arith.constant 10 : i32
      %ref = simulation.context.storage %ctx[1] : !int
      simulation.ref.store %period to %ref : i32, !int
      simulation.return %period : i32
    }
  }
}
