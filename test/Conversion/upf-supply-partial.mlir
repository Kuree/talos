// RUN: talos-opt %s --elaborate-upf --canonicalize --cse --verify-each | FileCheck %s --implicit-check-not=simulation.supply.control --implicit-check-not=upf.supply
// IEEE 1801-2018 11.2.3.3.4-.6: aliases converge on one root store; PARTIAL_ON
// retains state 2 and signed microvolt bits. Invalid states/voltages never
// store, and OFF does not convert a nonfinite voltage. Checks remain ordinary
// arithmetic and storage operations, so constant modes require no runtime ABI.
// 6.47: translation must not rewrite the physical state in this write path.
module attributes {upf.partial_on_translation = #upf.partial_on_translation<full_on>} {
  upf.supply @rail names ["/top/VDD", "/top/ALIAS"] writable = true
  upf.supply @protected names ["/top/SW"] writable = false
  simulation.design @supplies {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.partial"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.off"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.invalid_state"
    simulation.code_unit.decl 5 in 0 function hierarchy "top.invalid_voltage"
    simulation.code_unit.decl 6 in 0 function hierarchy "top.negative_state"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }

    // CHECK-LABEL: simulation.func @partial
    // CHECK: %[[STATE:.*]] = arith.constant 2 : i64
    // CHECK: simulation.string.literal "/top/VDD"
    // CHECK: cf.cond_br {{.*}}, [[MATCH:\^bb[0-9]+]], {{.*}}
    // CHECK: simulation.string.literal "/top/ALIAS"
    // CHECK: cf.cond_br {{.*}}, [[MATCH]], {{.*}}
    // CHECK: [[MATCH]]:
    // CHECK: simulation.real.to_integer
    // CHECK: arith.extui {{.*}} : i32 to i64
    // CHECK: %[[BITS:.*]] = arith.shli
    // CHECK: %[[VALUE:.*]] = arith.ori %[[BITS]], %[[STATE]] : i64
    // CHECK: simulation.ref.store %[[VALUE]] to {{.*}} : i64, !simulation.ref<i64>
    // CHECK-NOT: simulation.ref.store
    simulation.func @partial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %name: !simulation.string {simulation.capture_kind = 1 : i32},
        %voltage: f64 {simulation.capture_kind = 1 : i32}) -> i1
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %state = arith.constant 2 : i32
      %status = simulation.supply.control %ctx %name voltage %voltage state %state
      simulation.return %status : i1
    }

    // CHECK-LABEL: simulation.func @off
    // CHECK: %[[ZERO:.*]] = arith.constant 0 : i64
    // CHECK-NOT: simulation.real.to_integer
    // CHECK: simulation.ref.store %[[ZERO]] to {{.*}} : i64, !simulation.ref<i64>
    // CHECK-NOT: simulation.real.to_integer
    simulation.func @off(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %name: !simulation.string {simulation.capture_kind = 1 : i32}) -> i1
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %nan = arith.constant 0x7FF8000000000000 : f64
      %state = arith.constant 0 : i32
      %status = simulation.supply.control %ctx %name voltage %nan state %state
      simulation.return %status : i1
    }

    // CHECK-LABEL: simulation.func @invalid_state
    // CHECK-NOT: simulation.ref.store
    // CHECK: simulation.error
    // CHECK-NOT: simulation.ref.store
    // CHECK: simulation.return
    simulation.func @invalid_state(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %name: !simulation.string {simulation.capture_kind = 1 : i32}) -> i1
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %voltage = arith.constant 1.0 : f64
      %state = arith.constant 3 : i32
      %status = simulation.supply.control %ctx %name voltage %voltage state %state
      simulation.return %status : i1
    }

    // CHECK-LABEL: simulation.func @invalid_voltage
    // CHECK-NOT: simulation.ref.store
    // CHECK: simulation.error
    // CHECK-NOT: simulation.ref.store
    // CHECK: simulation.return
    simulation.func @invalid_voltage(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %name: !simulation.string {simulation.capture_kind = 1 : i32}) -> i1
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %voltage = arith.constant 0x7FF0000000000000 : f64
      %state = arith.constant 2 : i32
      %status = simulation.supply.control %ctx %name voltage %voltage state %state
      simulation.return %status : i1
    }

    // CHECK-LABEL: simulation.func @negative_state
    // CHECK-NOT: simulation.ref.store
    // CHECK: simulation.error
    // CHECK-NOT: simulation.ref.store
    // CHECK: simulation.return
    simulation.func @negative_state(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %name: !simulation.string {simulation.capture_kind = 1 : i32}) -> i1
        attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %voltage = arith.constant 1.0 : f64
      %state = arith.constant -1 : i32
      %status = simulation.supply.control %ctx %name voltage %voltage state %state
      simulation.return %status : i1
    }
  }
}
