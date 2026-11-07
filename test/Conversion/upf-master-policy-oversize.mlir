// RUN: not talos-opt %s --elaborate-upf --verify-each 2>&1 | FileCheck %s
// A single legal dialect-level packed type can exceed the LLVM backend cap.
// CHECK: master retention target exceeds supported packed width

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
    simulation.storage.decl 0 in 1 : !simulation.logic<8388609> design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.rtc"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 1 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %process = simulation.spawn @master_writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @master_writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8388609>>
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %old = simulation.ref.load %q : !simulation.ref<!simulation.logic<8388609>> -> !simulation.logic<8388609>
      simulation.nba.enqueue %old to %q : (!simulation.logic<8388609>, !simulation.ref<!simulation.logic<8388609>>) -> ()
      cf.br ^wait
    }
  }
}
