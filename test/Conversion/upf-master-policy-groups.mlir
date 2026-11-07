// RUN: talos-opt %s --elaborate-upf --canonicalize --cse --verify-each -o %t
// RUN: FileCheck %s --input-file=%t
// A legal N/Q pair can exceed the LLVM integer limit together. Split fields
// independently; group0 alone advances the epoch and prior policy state.
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.0.capture(
// CHECK-SAME: -> i66
// CHECK: arith.addi
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.0.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 3
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.1.capture(
// CHECK-SAME: -> i8388543
// CHECK-NOT: arith.addi
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.1.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 1
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.2.capture(
// CHECK-SAME: -> i8388543
// CHECK-NOT: arith.addi
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_retention.PD.R.policy.2.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 1

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
    simulation.storage.decl 0 in 1 : i8388543 design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.rtc"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 1 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %process = simulation.spawn @master_writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @master_writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<i8388543>
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %old = simulation.ref.load %q : !simulation.ref<i8388543> -> i8388543
      %one = arith.constant 1 : i8388543
      %next = arith.addi %old, %one : i8388543
      simulation.nba.enqueue %next to %q : (i8388543, !simulation.ref<i8388543>) -> ()
      cf.br ^wait
    }
  }
}
