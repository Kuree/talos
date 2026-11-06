// RUN: talos-opt %s --elaborate-upf --verify-diagnostics --verify-each
// A late raw-IR root write is not an HDL declaration initializer. Until that
// path has an independent output projection, reject it instead of publishing
// an unpowered output after the snapshot policy has already been installed.
#save = #upf.retention_trigger<control = #upf.token<opcode = control, control = "top.save">, kind = high>
module {
  upf.supply @p names ["/top/P"] writable = false {always_on = true, initial_value = 4000001 : i64}
  upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
  upf.supply_set @primary functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, associated = [@local]}
  upf.supply_set @local functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R", associated = [@primary]}
  upf.supply_set @ret functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R"}
  upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g, primary = @primary, policies = [@primary], retentions = [#upf.retention<name = "R", scope = "top", elements = [], excluded = [], retentionSupply = @ret, primarySupply = @local, domainDefault = true, save = #save>]}
  simulation.design @late_root {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 1 : i8 design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.save"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 1 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %process = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      %value = arith.constant 1 : i8
      // expected-error@+1 {{balloon retention root initialization after startup is not implemented}}
      simulation.ref.store %value to %q : i8, !simulation.ref<i8>
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %value = arith.constant 1 : i8
      simulation.nba.enqueue %value to %q : (i8, !simulation.ref<i8>) -> ()
      cf.br ^wait
    }
  }
}
