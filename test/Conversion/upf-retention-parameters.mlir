// RUN: talos-opt %s --split-input-file --canonicalize --cse --verify-each | talos-opt --split-input-file | FileCheck %s --check-prefix=INTENT
// RUN: talos-opt %s --split-input-file --prepare-upf-snapshot-publications --elaborate-upf --prepare-upf-snapshot-publications --canonicalize --cse --verify-each | FileCheck %s --check-prefix=LOWER
// IEEE 1801-2018 6.50: explicit negative parameters survive IR round trips.
// Balloon N updates do not require R when NO_RET_SUP_COR is set; master
// RET-powered outputs use independently guarded writes and normal self-reads.
// INTENT-COUNT-2: retentionSupplyCorrupt = false, saveRestoreCorrupt = false
// LOWER-LABEL: simulation.func private @__upf_balloon.PD.R.nba_allowed
// LOWER-NOT: simulation.context.storage {{.*}}[6]
// LOWER: simulation.return
// LOWER-LABEL: simulation.func private @master_writer
// LOWER: %[[OLD:.*]] = simulation.ref.load %[[NORMAL:.*]] : !simulation.ref<i8> -> i8
// LOWER: %[[NEW:.*]] = arith.addi %[[OLD]],
// LOWER: simulation.power.nba.enqueue_view {{.*}}, %[[NEW]] in %[[NORMAL]]
// LOWER-SAME: guard %[[NGUARD:[a-zA-Z0-9_]+]] epochs
// LOWER: %[[QGUARD:.*]] = simulation.observer.bind @__upf_retention.PD.R.update.output_allowed
// LOWER: %[[Q:.*]] = simulation.context.storage %arg0[0]
// LOWER: simulation.power.nba.enqueue_view {{.*}}, %[[NEW]] in %[[Q]]
// LOWER-SAME: guard %[[QGUARD]] epochs

#save = #upf.retention_trigger<control = #upf.token<opcode = control, control = "top.save">, kind = high>
#restore = #upf.retention_trigger<control = #upf.token<opcode = control, control = "top.restore">, kind = high>
module {
  upf.supply @p names ["/top/P"] writable = false {always_on = true, initial_value = 4000001 : i64}
  upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
  upf.supply @r names ["/top/R"] writable = true
  upf.supply_set @primary functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, associated = [@local]}
  upf.supply_set @local functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R", associated = [@primary]}
  upf.supply_set @ret functions {power = @r, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R"}
  upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g, primary = @primary, policies = [@primary], retentions = [#upf.retention<name = "R", scope = "top", elements = [], excluded = [], retentionSupply = @ret, primarySupply = @local, domainDefault = true, save = #save, restore = #restore, retentionSupplyCorrupt = false, saveRestoreCorrupt = false>]}
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
      %process = simulation.spawn @balloon_writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @balloon_writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
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

// -----

#rtc = #upf.expression<[#upf.token<opcode = control, control = "top.rtc">]>
module {
  upf.supply @p names ["/top/P"] writable = false {always_on = true, initial_value = 4000001 : i64}
  upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
  upf.supply @r names ["/top/R"] writable = true
  upf.supply_set @primary functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, associated = [@local]}
  upf.supply_set @local functions {power = @p, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R", associated = [@primary]}
  upf.supply_set @ret functions {power = @r, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g} required ["power", "ground"] {owner = @PD, strategy = "R"}
  upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g, primary = @primary, policies = [@primary], retentions = [#upf.retention<name = "R", scope = "top", elements = [], excluded = [], retentionSupply = @ret, primarySupply = @local, domainDefault = true, condition = #rtc, useRetentionAsPrimary = true, retentionSupplyCorrupt = false, saveRestoreCorrupt = false>]}
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
