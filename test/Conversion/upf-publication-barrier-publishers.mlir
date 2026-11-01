// RUN: talos-opt %s --prepare-upf-snapshot-publications | FileCheck %s
// IEEE 1801-2018 6.50: every operation that can publish synchronously gets
// a boundary, including zero-delay paths. Staging an NBA is not a commit.
// CHECK: simulation.ref.store
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.ref.copy
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.argument_ref.store
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.override
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.dynamic_override
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.release_override
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.net.write
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive_changed
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive_inertial
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive_inertial_path
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive_inertial_strength_pair
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive_inertial_path_strength_pair
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.driver.drive_delayed_net
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.net.pass.control
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.net.pass.control_delayed
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.net.mos.drive_delayed
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.supply.control
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.ref.store_inertial_path
// CHECK-NEXT: simulation.event.snapshot.flush
// CHECK: simulation.nba.enqueue
// CHECK-NEXT: simulation.ref.store_inertial_path {{.*}}nonblocking = true
// CHECK-NEXT: simulation.return
module attributes {simulation.snapshot_publications} {
  simulation.design @publishers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
    simulation.storage.decl 1 in 0 : !simulation.logic<1> design
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.net.decl 1 in 0 : !simulation.logic<1> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<1> design
    simulation.driver.decl 1 in 0 drives 0 : !simulation.logic<1> design
    simulation.net.pass.decl 0 in 0 0[0] to 1[0] width 1 reversed = false {controlled = true}
    simulation.net.pass.decl 1 in 0 0[0] to 1[0] width 1 reversed = false {controlled = true, directed = true, delayed = true}
    simulation.code_unit.decl 1 in 0 function hierarchy "top.publish"
    simulation.func @publish(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %owner: !simulation.process {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<1>>
      %other = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<1>>
      %arg = simulation.argument_ref.from_ref %ref : !simulation.ref<!simulation.logic<1>> -> !simulation.argument_ref<!simulation.logic<1>>
      %net = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<1>>
      %lo = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<1>>
      %hi = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.logic<1>>
      %v = simulation.logic.constant 1 : i1, 0 : i1 : !simulation.logic<1>
      %mask = arith.constant true
      %d = simulation.time.constant 0
      %name = simulation.string.literal "VDD"
      %voltage = arith.constant 1.0 : f64
      simulation.ref.store %v to %ref : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.ref.copy %ref to %other : !simulation.ref<!simulation.logic<1>>
      simulation.argument_ref.store %v to %arg : !simulation.logic<1>, !simulation.argument_ref<!simulation.logic<1>>
      simulation.override %ref = %v assign false : !simulation.ref<!simulation.logic<1>>, !simulation.logic<1>
      simulation.dynamic_override %ref = %v owner %owner assign false claim true : !simulation.ref<!simulation.logic<1>>, !simulation.logic<1>
      simulation.release_override %ref assign false : !simulation.ref<!simulation.logic<1>>
      simulation.net.write %net = %v : !simulation.net<!simulation.logic<1>>, !simulation.logic<1>
      simulation.driver.drive %lo = %v : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
      %changed = simulation.driver.drive_changed %lo = %v : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
      simulation.driver.drive_inertial %lo = %v after[%d,%d,%d] site 1 : 0 vector = false : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
      simulation.driver.drive_inertial_path %lo = %v active %mask masks[%mask,%mask,%mask] after[%d,%d,%d] site 1 : 1 group 0 of 1 : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>, i1
      simulation.driver.drive_inertial_strength_pair %lo = %v, %hi = %v transition %v after[%d,%d,%d] site 1 : 2 : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>, !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>, !simulation.logic<1>
      simulation.driver.drive_inertial_path_strength_pair %lo = %v, %hi = %v transition %v active %mask masks[%mask,%mask,%mask] after[%d,%d,%d] site 1 : 3 group 0 of 1 : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>, !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>, !simulation.logic<1>, i1
      simulation.driver.drive_delayed_net %lo = %v : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
      simulation.net.pass.control 0 = %v : !simulation.logic<1>
      simulation.net.pass.control_delayed 0 = %v after[%d,%d,%d] : !simulation.logic<1>
      simulation.net.mos.drive_delayed 1 = %v after[%d,%d,%d] : !simulation.logic<1>
      %on = simulation.supply.control %ctx %name voltage %voltage on %mask
      simulation.ref.store_inertial_path %v to %ref write %mask active %mask masks[%mask,%mask,%mask] after[%d,%d,%d] site 9 : 0 group 0 of 1 nonblocking = false : !simulation.ref<!simulation.logic<1>>, !simulation.logic<1>, i1
      simulation.nba.enqueue %v to %ref : (!simulation.logic<1>, !simulation.ref<!simulation.logic<1>>) -> ()
      simulation.ref.store_inertial_path %v to %ref write %mask active %mask masks[%mask,%mask,%mask] after[%d,%d,%d] site 9 : 1 group 0 of 1 nonblocking = true : !simulation.ref<!simulation.logic<1>>, !simulation.logic<1>, i1
      simulation.return
    }
  }
}
