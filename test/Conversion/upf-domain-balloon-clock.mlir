// RUN: talos-opt %s --prepare-upf-snapshot-publications --elaborate-upf --prepare-upf-snapshot-publications --canonicalize --cse --verify-each -o %t
// RUN: FileCheck %s --input-file=%t --implicit-check-not=__upf_clock.1.history --implicit-check-not=__upf_clock.1.owner
// RUN: talos-opt %t --canonicalize --cse --verify-each -o /dev/null
// A domain and a Balloon strategy share the original event's history/arm,
// while their qualification epochs/eligibility remain separate.
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_clock.1.epoch"
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_clock.1.valid"
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_balloon.PD.R.clock.0.epoch"
// CHECK-DAG: simulation.storage.decl {{.*}} "__upf_balloon.PD.R.clock.0.valid"
// CHECK-LABEL: simulation.func private @__upf_balloon.PD.R.clock.0.capture(
// CHECK-SAME: -> i132
// CHECK-NOT: simulation.context.storage
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_balloon.PD.R.clock.0.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 6 conditions 0 edges [0] indices [-1]
// CHECK: simulation.suspend.forever

#save = #upf.retention_trigger<control = #upf.token<opcode = control, control = "top.save">, kind = high>
#restore = #upf.retention_trigger<control = #upf.token<opcode = control, control = "top.restore">, kind = high>
module {
  upf.supply @p names ["/top/P"] writable = true {initial_value = 4000001 : i64}
  upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
  upf.supply_set @primary functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, associated = [@local]}
  upf.supply_set @local functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R", associated = [@primary]}
  upf.supply_set @ret functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R"}
  upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g, primary = @primary, policies = [@primary], retentions = [#upf.retention<name = "R", scope = "top", elements = [], excluded = [], retentionSupply = @ret, primarySupply = @local, domainDefault = true, save = #save, restore = #restore>]}
  simulation.design @balloon {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 1 : i8 design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.save"
    simulation.storage.decl 3 in 0 : i1 design hierarchy "top.restore"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 1 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %q = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %save = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %restore = simulation.context.storage %ctx[3] : !simulation.ref<i1>
      %zero = arith.constant 0 : i8
      %false = arith.constant false
      simulation.ref.store %zero to %q : i8, !simulation.ref<i8>
      simulation.ref.store %false to %clk : i1, !simulation.ref<i1>
      simulation.ref.store %false to %save : i1, !simulation.ref<i1>
      simulation.ref.store %false to %restore : i1, !simulation.ref<i1>
      %process = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
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
