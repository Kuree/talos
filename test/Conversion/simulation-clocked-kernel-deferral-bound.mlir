// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true}))' -o /dev/null 2>&1 | FileCheck %s

// Deferring a kernel takes a whole-design analysis, so a design with a clock
// class per instance defers only its largest kernels. Otherwise the pass grows
// with the square of the instances. Seventeen clocks here leave one undeferred.

// CHECK-COUNT-16: talos clocked kernel: {{.*}} deferred=1
// CHECK-NOT: deferred=1

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @bound {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.storage.decl 1 in 0 : !bit design {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.storage.decl 2 in 0 : !bit design {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.storage.decl 3 in 0 : !bit design {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 10 in 0 initial hierarchy "clock#" {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.code_unit.decl 11 in 0 always_ff hierarchy "toggle#" {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.code_unit.decl 12 in 0 always_ff hierarchy "follow#" {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.code_unit.decl 13 in 0 initial hierarchy "sampler#" {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}} : !ref
      %q = simulation.context.storage %ctx[1] {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}} : !ref
      %r = simulation.context.storage %ctx[2] {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}} : !ref
      %seen = simulation.context.storage %ctx[3] {test.replicate = 17 : i64, test.replicate_stride = {id = 4 : i64}} : !ref
      %p0 = simulation.spawn @"clock_#"(%ctx, %clk) {test.replicate = 17 : i64} : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @"toggle_#"(%ctx, %clk, %q) {test.replicate = 17 : i64} : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @"follow_#"(%ctx, %clk, %q, %r) {test.replicate = 17 : i64} : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @"sampler_#"(%ctx, %clk, %q, %seen) {test.replicate = 17 : i64} : !simulation.context, !ref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @"clock_#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 10 : i64, test.replicate = 17 : i64, test.replicate_stride = {code_unit_id = 4 : i64, "simulation.descriptor_id" = 4 : i64}} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.ref.store %one to %clk : !bit, !ref
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^low
    }
    simulation.func private @"toggle_#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 11 : i64, test.replicate = 17 : i64, test.replicate_stride = {code_unit_id = 4 : i64, "simulation.descriptor_id" = 4 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @"follow_#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 12 : i64, test.replicate = 17 : i64, test.replicate_stride = {code_unit_id = 4 : i64, "simulation.descriptor_id" = 4 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %q : !ref -> !bit
      simulation.nba.enqueue %v to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @"sampler_#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 13 : i64, test.replicate = 17 : i64, test.replicate_stride = {code_unit_id = 4 : i64, "simulation.descriptor_id" = 4 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %q : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      cf.br ^wait
    }
  }
}
