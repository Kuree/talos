// RUN: talos-opt %s --prepare-upf-snapshot-publications --elaborate-upf --prepare-upf-snapshot-publications --verify-each -o %t
// RUN: FileCheck %s --input-file=%t --implicit-check-not=simulation.scheduler.cohort
// RUN: talos-opt %t --canonicalize --cse --verify-each --canonicalize --cse --verify-each -o /dev/null
// Original wait operands, site, region and repeating-loop identity survive.
// Frozen epoch/eligibility guards precede all original activation operations.
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_clock.55.epoch"
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_clock.55.valid"
// CHECK-DAG: simulation.storage.decl {{.*}} : i1 {{.*}} "__upf_clock.55.history"
// CHECK-LABEL: simulation.func private @writer
// CHECK: simulation.ref.store {{.*}} : i1, !simulation.ref<i1>
// CHECK: simulation.suspend.edge posedge {{.*}} to {{.*}}({{.*}} : i8)
// CHECK-SAME: resume_region = 3 : i32
// CHECK-SAME: schedule.repeating_always_wait
// CHECK-SAME: site = #schedule.continuation<id = 91>
// CHECK: arith.cmpi eq
// CHECK: arith.andi
// CHECK: cf.cond_br
// CHECK: simulation.power.nba.enqueue_view
// CHECK-LABEL: simulation.func private @__upf_clock.55(
// CHECK-SAME: -> i1
// CHECK-LABEL: simulation.func private @__upf_clock.55.capture(
// CHECK-SAME: -> i67
// CHECK-NOT: simulation.context.storage
// CHECK: arith.select
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_clock.55.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 4 conditions 0 edges [0] indices [-1]
// CHECK: simulation.suspend.forever

#rtc = #upf.expression<[#upf.token<opcode = control, control = "top.rtc">]>
module {
  upf.supply @p names ["/top/P"] writable = true
  upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
  upf.supply_set @primary functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, associated = [@local]}
  upf.supply_set @local functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R", associated = [@primary]}
  upf.supply_set @ret functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R"}
  upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g, primary = @primary, policies = [@primary], retentions = [#upf.retention<name = "R", scope = "top", elements = [], excluded = [], retentionSupply = @ret, primarySupply = @local, noRetention = true, domainDefault = true>]}
  simulation.design @process {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 1 : i8 design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 2 in 0 : i8 design hierarchy "top.outside"
    simulation.storage.decl 3 in 0 : i1 design hierarchy "top.rtc"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 55 in 1 always hierarchy "top.dut.writer" {source_process = "top.dut.P"}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %process = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 55 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %outside = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^wait
    ^wait:
      %v = arith.constant 1 : i8
      simulation.suspend.edge posedge %clk to ^body(%v : i8) {resume_region = 3 : i32, schedule.repeating_always_wait, site = #schedule.continuation<id = 91>} : !simulation.ref<i1>
    ^body(%value: i8):
      simulation.nba.enqueue %value to %q : (i8, !simulation.ref<i8>) -> ()
      simulation.nba.enqueue %value to %outside : (i8, !simulation.ref<i8>) -> ()
      cf.br ^wait
    }
  }
}
