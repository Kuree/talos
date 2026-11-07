// RUN: talos-opt %s --elaborate-upf --canonicalize --cse --verify-each -o %t
// RUN: FileCheck %s --input-file=%t
// Change watches the whole packed expression, including upper-bit and X/Z
// changes, unlike directed edges' LSB rule (IEEE 1800-2023 9.4.2).
// CHECK-DAG: simulation.storage.decl {{.*}} : !simulation.logic<65> {{.*}} "__upf_clock.55.history"
// CHECK-LABEL: simulation.func private @__upf_clock.55.capture(
// CHECK-NOT: simulation.context.storage
// CHECK: simulation.logic.compare case_ne
// CHECK-SAME: !simulation.logic<65>
// CHECK: simulation.return
// CHECK-LABEL: simulation.func private @__upf_clock.55.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: !simulation.observer<!simulation.logic<131>>

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
    simulation.storage.decl 1 in 0 : !simulation.logic<65> design hierarchy "top.clk"
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
      %clk = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<65>>
      %enable = simulation.context.storage %ctx[3] : !simulation.ref<i1>
      %outside = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^wait
    ^wait:
      %v = arith.constant 1 : i8
      simulation.suspend.edge_iff change %clk iff %enable to ^body(%v : i8) {resume_region = 3 : i32, schedule.repeating_always_wait, site = #schedule.continuation<id = 91>} : !simulation.ref<!simulation.logic<65>>, !simulation.ref<i1>
    ^body(%value: i8):
      simulation.nba.enqueue %value to %q : (i8, !simulation.ref<i8>) -> ()
      simulation.nba.enqueue %value to %outside : (i8, !simulation.ref<i8>) -> ()
      cf.br ^wait
    }
  }
}
