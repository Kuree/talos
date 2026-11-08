#narrow = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [15, 0], children = [], childNames = []>
#wide = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [79, 0], children = [], childNames = []>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @static_change_targets {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.scope.decl 1 parent 0 hierarchy "top" vpi_kind 32
    simulation.storage.decl 0 in 1 : !simulation.logic<16> design hierarchy "top.value" {vpi_type = #narrow}
    simulation.storage.decl 1 in 1 : !simulation.logic<80> design hierarchy "top.wide" {vpi_type = #wide}
    simulation.code_unit.decl 1 in 1 root_initializer hierarchy "top.root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}
