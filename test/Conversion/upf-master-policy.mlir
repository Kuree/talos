// RUN: talos-opt %s --prepare-upf-snapshot-publications --elaborate-upf --prepare-upf-snapshot-publications --canonicalize --cse --verify-each -o %t
// RUN: FileCheck %s --input-file=%t --implicit-check-not=simulation.process.event_pending --implicit-check-not=simulation.power.cancel_nba --implicit-check-not='cancel_indices = array<i32:' --implicit-check-not=__upf_retention.PD.R.bad --implicit-check-not=__upf_retention.PD.R.freeze --implicit-check-not=__upf_retention.PD.R.monitor
// RUN: talos-opt %t --canonicalize --cse --verify-each -o /dev/null
// One exact policy epoch, immutable closed callbacks and no delayed policy
// actors. Domain and master validity share history but retain separate fields.
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_retention.PD.R.previous_writable"
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_retention.PD.R.previous_bad"
// CHECK-LABEL: simulation.func private @master_writer
// CHECK: simulation.suspend.edge posedge
// CHECK: arith.cmpi eq
// CHECK: cf.cond_br
// CHECK: simulation.power.nba.enqueue
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy(
// CHECK-SAME: -> i3
// CHECK-NOT: simulation.context.storage
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.0.capture(
// CHECK-SAME: -> i82
// CHECK-NOT: simulation.context.storage
// CHECK: arith.addi
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.0.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 5 conditions 0 edges [0] indices [-1]
// CHECK: simulation.suspend.forever
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.clock.0.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 6 conditions 0 edges [0] indices [-1]

#rtc = #upf.expression<[#upf.token<opcode = control, control = "top.rtc">]>
module {
  upf.supply @p names ["/top/P"] writable = true {initial_value = 4000001 : i64}
  upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
  upf.supply @r names ["/top/R"] writable = true
  upf.supply_set @primary functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, associated = [@local]}
  upf.supply_set @local functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R", associated = [@primary]}
  upf.supply_set @ret functions {power = @r, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R"}
  upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g, primary = @primary, policies = [@primary], retentions = [#upf.retention<name = "R", scope = "top", elements = [], excluded = [], retentionSupply = @ret, primarySupply = @local, domainDefault = true, condition = #rtc, useRetentionAsPrimary = true>]}
  simulation.design @master {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 1 : i8 design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.rtc"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 1 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %process = simulation.spawn @master_writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @master_writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %old = simulation.ref.load %q : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.nba.enqueue %next to %q : (i8, !simulation.ref<i8>) -> ()
      cf.br ^wait
    }
  }
}
