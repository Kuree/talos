// RUN: talos-opt %s --talos-sim-thread-runtime-statuses | FileCheck %s

// IEEE 1800-2023 21.2.2: starting a $strobe display is a cold runtime exit of
// the strobing activation, like a deferred assertion report (16.4.1). A
// function holding such a spawn (marked simulation.postponed_display) gets the
// runtime status channel, so a generated eval body takes its checkpoint. An
// unmarked spawn does not.

module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @d {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "d.owner"
    simulation.code_unit.decl 2 in 0 fork hierarchy "d.display"
    simulation.code_unit.decl 3 in 0 function hierarchy "d.plain"
    simulation.func private @owner(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, domain = 0 : i32, entry_kind = 8 : i32, home_region = 2 : i32} {
      %p = schedule.spawn @display(%ctx) {simulation.postponed_display} : !simulation.context -> i64
      simulation.return
    }
    simulation.func private @plain(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 3 : i64, domain = 0 : i32, entry_kind = 8 : i32, home_region = 2 : i32} {
      %p = schedule.spawn @display(%ctx) : !simulation.context -> i64
      simulation.return
    }
    simulation.func private @display(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 2 : i64, domain = 0 : i32, entry_kind = 13 : i32, home_region = 16 : i32} {
      simulation.return
    }
  }
}

// CHECK-LABEL: simulation.func private @owner(
// CHECK-SAME: -> i32
// CHECK: simulation.return %{{.*}} : i32
// CHECK-LABEL: simulation.func private @plain(
// CHECK-NOT: -> i32
// CHECK: simulation.return{{$}}
