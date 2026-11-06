// RUN: talos-opt %s --elaborate-upf --canonicalize --cse --verify-each -o %t
// RUN: talos-opt %t --canonicalize --cse --verify-each | FileCheck %s
// CHECK-LABEL: simulation.func private @__upf_PD.loss.0.capture
// CHECK: arith.addi
// CHECK-LABEL: simulation.func private @__upf_PD.loss.0.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 2
// CHECK-SAME: cancel_indices = array<i32>
// CHECK-LABEL: simulation.func private @__upf_PD.loss.1.capture
// CHECK-NOT: arith.addi
// CHECK-LABEL: simulation.func private @__upf_PD.loss.1.owner
// CHECK: simulation.event.snapshot.register
// CHECK-SAME: targets 1
// CHECK-SAME: cancel_indices = array<i32: 0>

module {
 upf.supply @p names ["/top/P"] writable = true
 upf.supply @g names ["/top/G"] writable = false {always_on = true, initial_value = 1 : i64}
 upf.domain @PD elements ["top.dut"] power @p on [] {ground = @g}
 simulation.design @large {
  simulation.scope.decl 0 hierarchy "top"
  simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
  simulation.storage.decl 0 in 1 : i8388600 design hierarchy "top.dut.q"
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
   %q = simulation.context.storage %ctx[0] : !simulation.ref<i8388600>
   simulation.return
  }
 }
}
