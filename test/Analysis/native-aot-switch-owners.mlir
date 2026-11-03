// RUN: talos-opt %s -split-input-file -o /dev/null \
// RUN:   --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),test-talos-native-aot-analysis)' \
// RUN:   2>&1 | FileCheck %s
// RUN: talos-opt %s -split-input-file -o /dev/null \
// RUN:   --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native_scheduler = 3 : i32}"},simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),test-talos-native-aot-analysis)' \
// RUN:   2>&1 | FileCheck %s --check-prefix=EVAL

// IEEE 1800-2023 4.9.5, 28.8: a switch's control change re-resolves every
// node the switch connects. The runtime owns that topology change, so only
// the process that makes it leaves the generated plan; an unrelated process
// keeps its slot (two-tier P1e).
// CHECK-LABEL: native-aot eligible=true fully=false
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @unrelated
// CHECK-NEXT: bytecode @control bb0
// CHECK-NEXT: reason switch control is runtime-owned

module {
  simulation.design @pass_control_owner {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.net.decl 1 in 0 : !simulation.logic<1> design
    simulation.net.pass.decl 0 in 0 0[0] to 1[0] width 1 reversed = false {
      controlled = true
    }
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "control"
    simulation.code_unit.decl 3 in 0 initial hierarchy "unrelated"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %control = simulation.spawn @control(%ctx) : !simulation.context -> !simulation.process
      %unrelated = simulation.spawn @unrelated(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }

    simulation.func @control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %one = simulation.logic.constant true, false : !simulation.logic<1>
      simulation.net.pass.control 0 = %one : !simulation.logic<1>
      simulation.return
    }

    simulation.func @unrelated(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      simulation.return
    }
  }
}

// -----

// A delayed control publication or MOS contribution changes connectivity from
// a runtime calendar event (28.16); only the process that schedules it is
// runtime-owned.
// CHECK-LABEL: native-aot eligible=true fully=false
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @unrelated
// CHECK-NEXT: bytecode @control bb0
// CHECK-NEXT: bytecode @mos bb0
// CHECK-NEXT: reason delayed switch contribution is runtime-owned

module {
  simulation.design @delayed_pass_owner {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.net.decl 1 in 0 : !simulation.logic<1> design
    simulation.net.pass.decl 0 in 0 0[0] to 1[0] width 1 reversed = false {
      controlled = true
    }
    simulation.net.pass.decl 1 in 0 0[0] to 1[0] width 1 reversed = false {
      controlled = true, delayed = true, directed = true
    }
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "control"
    simulation.code_unit.decl 3 in 0 initial hierarchy "unrelated"
    simulation.code_unit.decl 4 in 0 initial hierarchy "mos"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %control = simulation.spawn @control(%ctx) : !simulation.context -> !simulation.process
      %unrelated = simulation.spawn @unrelated(%ctx) : !simulation.context -> !simulation.process
      %mos = simulation.spawn @mos(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }

    simulation.func @mos(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %one = simulation.logic.constant true, false : !simulation.logic<1>
      %delay = simulation.time.constant 2
      simulation.net.mos.drive_delayed 1 = %one after[%delay, %delay, %delay] : !simulation.logic<1>
      simulation.return
    }

    simulation.func @control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %one = simulation.logic.constant true, false : !simulation.logic<1>
      %on = simulation.time.constant 3
      %off = simulation.time.constant 5
      %unknown = simulation.time.constant 3
      simulation.net.pass.control_delayed 0 = %one
          after[%on, %off, %unknown] : !simulation.logic<1>
      simulation.return
    }

    simulation.func @unrelated(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      simulation.return
    }
  }
}

// -----

// IEEE 1800-2023 28.8, 28.13: once pass switches connect components, the
// runtime resolves every driven net after each publication, which a generated
// eval owner cannot call. In the plans that may become eval plans, a process
// that drives a net is runtime-owned; outside them it keeps its slot.
// CHECK-LABEL: native-aot eligible=true fully=true
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @drive
// CHECK-NEXT: actor 2 @bystander
// EVAL-NOT: actor {{[0-9]+}} @drive
// EVAL: actor 1 @bystander
// EVAL-NEXT: bytecode @drive bb0
// EVAL-NEXT: reason net resolution is runtime-owned

module {
  simulation.design @pass_driver_owner {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.net.decl 1 in 0 : !simulation.logic<1> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<1> design
    simulation.net.pass.decl 0 in 0 0[0] to 1[0] width 1 reversed = false
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "drive"
    simulation.code_unit.decl 3 in 0 initial hierarchy "bystander"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %drive = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      %unrelated = simulation.spawn @bystander(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }

    simulation.func @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<1>>
      %one = simulation.logic.constant true, false : !simulation.logic<1>
      simulation.driver.drive %driver = %one : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
      simulation.return
    }

    simulation.func @bystander(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      simulation.return
    }
  }
}

// -----

// A delayed net (6.7, 28.16) schedules its own calendar update in the
// runtime, which a generated eval owner cannot call: in the plans that may
// become eval plans its driving process is runtime-owned, without any pass
// switch; outside them it keeps its slot.
// CHECK-LABEL: native-aot eligible=true fully=true
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @delayed_drive
// CHECK-NEXT: actor 2 @onlooker
// EVAL-NOT: actor {{[0-9]+}} @delayed_drive
// EVAL: actor 1 @onlooker
// EVAL-NEXT: bytecode @delayed_drive bb0
// EVAL-NEXT: reason net resolution is runtime-owned

module {
  simulation.design @delayed_net_owner {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !simulation.logic<1> design {
      propagation_delays = array<i64: 3, 3, 3>
    }
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<1> design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "delayed_drive"
    simulation.code_unit.decl 3 in 0 initial hierarchy "onlooker"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %drive = simulation.spawn @delayed_drive(%ctx) : !simulation.context -> !simulation.process
      %onlooker = simulation.spawn @onlooker(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }

    simulation.func @delayed_drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<1>>
      %one = simulation.logic.constant true, false : !simulation.logic<1>
      simulation.driver.drive_delayed_net %driver = %one : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
      simulation.return
    }

    simulation.func @onlooker(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      simulation.return
    }
  }
}
