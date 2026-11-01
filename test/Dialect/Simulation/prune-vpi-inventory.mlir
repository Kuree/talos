// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-prune-vpi-inventory))' | FileCheck %s
// Only a design database reads VPI relations, and without a VPI profile only a
// waveform dump needs one.

module {
  // CHECK-LABEL: simulation.design @pruned
  // CHECK-SAME: simulation.vpi_inventory_pruned
  // CHECK-NOT: vpi_net_identity.decl
  // CHECK-NOT: vpi_relation.decl
  // CHECK: simulation.statement.decl 1
  // CHECK: simulation.net.decl 0
  // CHECK-NOT: vpi_relation.decl
  simulation.design @pruned {
    simulation.scope.decl 0 hierarchy "top" vpi_kind 32
    simulation.statement.decl 1 scope 0 type 8 loc("relation.sv":1:1)
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
        hierarchy "top.lhs" debug "lhs" {
      vpi_type = #simulation.vpi_type<kind = logic, isSigned = false,
          isFourState = true, range = [0, 0], children = [], childNames = []>
    }
    simulation.vpi_net_identity.decl 0 backed_by 0 in 0
        : !simulation.logic<1> hierarchy "top.alias" debug "alias" {
      vpi_type = #simulation.vpi_type<kind = logic, isSigned = false,
          isFourState = true, range = [0, 0], children = [], childNames = []>
    }
    simulation.vpi_relation.decl <kind = net_identity, id = 0 : i64>
        selector 126 handle ordinal 0 to <kind = net, id = 0 : i64>
  }
}

// -----

module {
  // CHECK-LABEL: simulation.design @dumps
  // CHECK-NOT: simulation.vpi_inventory_pruned
  // CHECK: vpi_net_identity.decl
  // CHECK: vpi_relation.decl
  simulation.design @dumps {
    simulation.scope.decl 0 hierarchy "top" vpi_kind 32
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
        hierarchy "top.lhs" debug "lhs" {
      vpi_type = #simulation.vpi_type<kind = logic, isSigned = false,
          isFourState = true, range = [0, 0], children = [], childNames = []>
    }
    simulation.vpi_net_identity.decl 0 backed_by 0 in 0
        : !simulation.logic<1> hierarchy "top.alias" debug "alias" {
      vpi_type = #simulation.vpi_type<kind = logic, isSigned = false,
          isFourState = true, range = [0, 0], children = [], childNames = []>
    }
    simulation.vpi_relation.decl <kind = net_identity, id = 0 : i64>
        selector 126 handle ordinal 0 to <kind = net, id = 0 : i64>
    simulation.code_unit.decl 5 in 0 port_input hierarchy "flush"
    simulation.func @flush(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 9 : i32, code_unit_id = 5 : i64} {
      simulation.dump.flush %ctx : (!simulation.context) -> ()
      simulation.return
    }
  }
}
