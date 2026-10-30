// RUN: talos-opt %s --split-input-file --verify-diagnostics
// Immutable provenance must only mark input-connection code units.
module {
  // expected-error @+1 {{computed input metadata requires an input connection code unit}}
  simulation.code_unit.decl 1 in 0 always hierarchy "top.actor" {simulation.computed_port_input}
}

// -----
module {
  simulation.code_unit.decl 1 in 0 port_input hierarchy "top.child.$port_connection_0" {internal, simulation.computed_port_input}
  simulation.code_unit.decl 2 in 0 port_initialize hierarchy "top.child.$port_connection_1" {internal, simulation.computed_port_input}
}
