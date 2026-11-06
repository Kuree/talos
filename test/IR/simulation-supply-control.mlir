// RUN: talos-opt %s --canonicalize --cse | talos-opt | FileCheck %s
// IEEE 1801-2018 11.2.3.3.6: partial writes retain effects even if status
// results are discarded. Duplicate writes can each report a runtime error;
// CSE must preserve them and their order relative to immediate queries.
// CHECK-LABEL: simulation.func @control
// CHECK: %[[PARTIAL:.*]] = arith.constant 2 : i32
// CHECK: simulation.supply.read
// CHECK: simulation.supply.control {{.*}} state %[[PARTIAL]]
// CHECK: simulation.supply.control {{.*}} state %[[PARTIAL]]
// CHECK: simulation.supply.read
module {
  simulation.func @control(
      %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
      %name: !simulation.string {simulation.capture_kind = 1 : i32},
      %voltage: f64 {simulation.capture_kind = 1 : i32}) -> i64
      attributes {entry_kind = 8 : i32} {
    %partial = arith.constant 2 : i32
    %first = simulation.supply.read %ctx %name
    %status = simulation.supply.control %ctx %name voltage %voltage state %partial
    %duplicate = simulation.supply.control %ctx %name voltage %voltage state %partial
    %last = simulation.supply.read %ctx %name
    simulation.return %last : i64
  }
}
