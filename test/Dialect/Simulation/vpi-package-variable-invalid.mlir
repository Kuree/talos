// RUN: talos-opt %s --split-input-file --verify-diagnostics

#word = #simulation.vpi_type<kind = int, isSigned = true, isFourState = false, range = [31, 0], children = [], childNames = []>
module {
  simulation.design @wrong_owner {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.scope.decl 1 parent 0 hierarchy "top" vpi_kind 32
    simulation.vpi_object.anchor @top id 0 type 32 in 1 ordinal 0 hierarchy "top" debug "top" {backing = #simulation.vpi_backing<kind = scope, id = 1 : i64>}
    simulation.storage.decl 0 in 1 : i32 design hierarchy "top.x" debug "x" {vpi_type = #word}
    // expected-error @+1 {{variable storage anchor requires a package owner in its enclosing scope}}
    simulation.vpi_object.anchor @x id 1 type 612 in 1 parent @top ordinal 0 hierarchy "top.x" debug "x" {backing = #simulation.vpi_backing<kind = storage, id = 0 : i64>}
  }
}

// -----

#word = #simulation.vpi_type<kind = int, isSigned = true, isFourState = false, range = [31, 0], children = [], childNames = []>
module {
  simulation.design @wrong_kind {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.vpi_object.anchor @pkg id 0 type 600 in 0 ordinal 0 hierarchy "pkg" debug "pkg"
    simulation.storage.decl 0 in 0 : i32 design hierarchy "pkg::x" debug "x" {vpi_type = #word}
    // expected-error @+1 {{package variable anchor requires matching design storage, VPI kind, and declaration name}}
    simulation.vpi_object.anchor @x id 1 type 611 in 0 parent @pkg ordinal 0 hierarchy "pkg::x" debug "x" {backing = #simulation.vpi_backing<kind = storage, id = 0 : i64>}
  }
}

// -----

#word = #simulation.vpi_type<kind = int, isSigned = true, isFourState = false, range = [31, 0], children = [], childNames = []>
module {
  simulation.design @wrong_name {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.vpi_object.anchor @pkg id 0 type 600 in 0 ordinal 0 hierarchy "pkg" debug "pkg"
    simulation.storage.decl 0 in 0 : i32 design hierarchy "pkg::x" debug "x" {vpi_type = #word}
    // expected-error @+1 {{package variable anchor requires matching design storage, VPI kind, and declaration name}}
    simulation.vpi_object.anchor @x id 1 type 612 in 0 parent @pkg ordinal 0 hierarchy "pkg::x" debug "y" {backing = #simulation.vpi_backing<kind = storage, id = 0 : i64>}
  }
}
