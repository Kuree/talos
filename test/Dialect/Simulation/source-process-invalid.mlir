// RUN: talos-opt %s --split-input-file --verify-diagnostics
module {
  simulation.design @empty {
    simulation.scope.decl 0 hierarchy "top"
    // expected-error @+1 {{source process name must be nonempty}}
    simulation.code_unit.decl 1 in 0 always hierarchy "top.stable" {source_process = ""}
  }
}

// -----
module {
  simulation.design @helper {
    simulation.scope.decl 0 hierarchy "top"
    // expected-error @+1 {{source process name requires a procedural code unit}}
    simulation.code_unit.decl 1 in 0 function hierarchy "top.stable" {source_process = "top.P"}
  }
}

// -----
module {
  simulation.design @duplicate {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 always hierarchy "top.stable1" {source_process = "top.P"}
    // expected-error @+1 {{duplicates a source process name: top.P}}
    simulation.code_unit.decl 2 in 0 always hierarchy "top.stable2" {source_process = "top.P"}
  }
}

// -----
module {
  simulation.design @scope {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut"
    // expected-error @+1 {{source process must be nested in the code unit's scope}}
    simulation.code_unit.decl 1 in 1 always hierarchy "top.dut.stable" {source_process = "top.other.P"}
  }
}
