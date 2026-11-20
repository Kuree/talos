// RUN: talos-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{has undeclared attribute 'dpi.is_task'}}
func.func private @undeclared() attributes {dpi.is_task = true}

// -----

// expected-error @+1 {{attribute 'dpi.c_identifier' has the wrong payload kind}}
func.func private @wrong_kind() attributes {dpi.c_identifier = 3 : i32}

// -----

// expected-error @+1 {{attribute 'dpi.import_id' must be a nonzero 32-bit identity}}
func.func private @zero_id() attributes {dpi.import_id = 0 : i32}

// -----

// expected-error @+1 {{attribute 'dpi.abi_signature' must contain only #dpi.abi entries}}
func.func private @untyped_signature() attributes {
  dpi.abi_signature = [1 : i32]}

// -----

// expected-error @+1 {{attribute 'dpi.aggregate_layouts' must have one entry per ABI signature entry}}
func.func private @layout_count() attributes {
  dpi.abi_signature = [#dpi.abi<kind = int, direction = input, width = 32,
                                fourState = false, isSigned = true>],
  dpi.aggregate_layouts = [unit, unit]}

// -----

// expected-error @+1 {{attribute 'dpi.logical_inputs' exceeds the ABI signature}}
func.func private @logical_inputs() attributes {
  dpi.abi_signature = [], dpi.logical_inputs = 1 : i32}

// -----

// expected-error @+1 {{attribute 'dpi.elided_inputs' must be strictly increasing formal indices}}
func.func private @elided() attributes {dpi.elided_inputs = array<i64: 2, 1>}

// -----

// expected-error @+1 {{attribute 'dpi.has_exports' belongs on a module}}
func.func private @exports() attributes {dpi.has_exports}

// -----

func.func private @abi() attributes {
  // expected-error @+1 {{DPI ABI category requires width 32}}
  layout = #dpi.abi<kind = int, direction = input, width = 8,
                    fourState = false, isSigned = true>}

// -----

// expected-error @+1 {{'dpi.lexical_scopes' belongs on the root scope of a simulation design}}
func.func private @misplaced() attributes {dpi.lexical_scopes = []}

// -----

simulation.design @nonroot {
  simulation.scope.decl 0
  // expected-error @+1 {{'dpi.lexical_scopes' belongs on the root scope of a simulation design}}
  simulation.scope.decl 1 parent 0 {dpi.lexical_scopes = []}
}

// -----

simulation.design @wrong_entry {
  // expected-error @+1 {{must contain only #dpi.scope entries}}
  simulation.scope.decl 0 {dpi.lexical_scopes = ["pkg"]}
}

// -----

// expected-error @+1 {{DPI scope requires a nonempty name without NUL bytes}}
#empty = #dpi.scope<parent = 0, name = "", unitFs = 1000, precisionFs = 1>
module {}

// -----

// expected-error @+1 {{DPI scope requires a nonempty name without NUL bytes}}
#nul = #dpi.scope<parent = 0, name = "a\00b", unitFs = 1000, precisionFs = 1>
module {}

// -----

// expected-error @+1 {{DPI time scales must be decimal powers from 1 fs to 100 s}}
#invalid_unit = #dpi.scope<parent = 0, name = "pkg", unitFs = 12, precisionFs = 1>
module {}

// -----

// expected-error @+1 {{DPI scope time unit is finer than its precision}}
#invalid_precision = #dpi.scope<parent = 0, name = "pkg", unitFs = 1000, precisionFs = 1000000>
module {}

// -----

simulation.design @global_precision attributes {time_precision_fs = 1000 : i64} {
  // expected-error @+1 {{DPI scope precision is finer than the design precision}}
  simulation.scope.decl 0 {dpi.lexical_scopes = [
    #dpi.scope<parent = 0, name = "pkg", unitFs = 1000, precisionFs = 1>]}
}

// -----

simulation.design @parent {
  // expected-error @+1 {{DPI scope parent must precede its child}}
  simulation.scope.decl 0 {dpi.lexical_scopes = [
    #dpi.scope<parent = 2, name = "top.g", unitFs = 1000000, precisionFs = 1000000>]}
  simulation.scope.decl 1 parent 0 hierarchy "top"
}

// -----

simulation.design @duplicate {
  // expected-error @+1 {{duplicate DPI scope name "top"}}
  simulation.scope.decl 0 {dpi.lexical_scopes = [
    #dpi.scope<parent = 1, name = "top", unitFs = 1000000, precisionFs = 1000000>]}
  simulation.scope.decl 1 parent 0 hierarchy "top"
}
