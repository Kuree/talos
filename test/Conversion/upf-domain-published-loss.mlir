// RUN: talos-opt %s --prepare-upf-snapshot-publications --elaborate-upf --prepare-upf-snapshot-publications --canonicalize --cse --verify-each -o %t
// RUN: talos-opt %t --canonicalize --cse --verify-each | FileCheck %s --implicit-check-not=upf.domain
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_PD.epoch"
// CHECK-DAG: simulation.func private @__upf_PD.loss.0.power
// CHECK: simulation.func private @__upf_PD.loss.0.capture
// CHECK-NOT: simulation.context.storage
// CHECK: arith.addi
// CHECK: simulation.return
// CHECK: simulation.func private @__upf_PD.loss.0.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 3
// CHECK-SAME: edges [2]
// CHECK-SAME: cancel_indices = array<i32: 2>
// CHECK: simulation.suspend.forever
// CHECK: simulation.func private @__upf_PD.monitor
// CHECK-NOT: simulation.power.cancel_nba
// CHECK-NOT: arith.addi
// CHECK: simulation.suspend.any

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
    simulation.code_unit.decl 55 in 0 always hierarchy "top.stable_55" {source_process = "top.P"}
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
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %value = arith.constant 1 : i8
      simulation.nba.enqueue %value to %q : (i8, !simulation.ref<i8>) -> ()
      simulation.nba.enqueue %value to %outside : (i8, !simulation.ref<i8>) -> ()
      cf.br ^wait
    }
  }
}
