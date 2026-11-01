// RUN: talos-opt %s --split-input-file --prepare-upf-snapshot-publications --verify-diagnostics --allow-unregistered-dialect
// IEEE 1801-2018 6.50: fail before mutation when publication boundaries
// cannot be proved, callback execution cannot flush, or images are frozen.

// expected-error @+1 {{simulation.snapshot_publications}}
module attributes {simulation.snapshot_publications = 1 : i32} {}

// -----

module {
  // expected-error @+1 {{belongs on a module}}
  simulation.design @wrong attributes {simulation.snapshot_publications} {}
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 2 in 0 function hierarchy "top.foreign"
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      // expected-error @+1 {{snapshot publications require defined compiled call targets}}
      simulation.call @foreign(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func private @foreign(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64}
  }
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      // expected-error @+1 {{snapshot publication boundaries for context DPI imports are not implemented}}
      %status = simulation.dpi.call "opaque" id 1 scope 0 context %ctx : !simulation.context() {abi_signature = [], is_context = true, is_pure = false, is_task = false, source_column = 1 : i32, source_file = "x.sv", source_line = 1 : i32} : () -> !runtime.status
      simulation.return
    }

  }
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      // expected-error @+1 {{snapshot publications require defined compiled call targets}}
      func.call @foreign() : () -> ()
      simulation.return
    }
    func.func private @foreign()
  }
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.observe"
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }
        // expected-note @+1 {{observer callback is declared here}}
    simulation.func private @observe(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %false = arith.constant false
      // expected-error @+1 {{snapshot callbacks require an inspectable closure without persistent publications}}
      simulation.ref.store %false to %ref : i1, !simulation.ref<i1>
      %true = arith.constant true
      simulation.return %true : i1
    }

  }
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.observe"
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      // expected-error @+1 {{snapshot callbacks require an inspectable closure without persistent publications}}
      simulation.event.snapshot.flush %ctx
      simulation.return
    }
        // expected-note @+1 {{observer callback is declared here}}
    simulation.func private @observe(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      simulation.call @main(%ctx) : (!simulation.context) -> ()
      %true = arith.constant true
      simulation.return %true : i1
    }

  }
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 2 in 0 observer hierarchy "top.observe"
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %false = arith.constant false
      // expected-error @+1 {{snapshot callbacks require an inspectable closure without persistent publications}}
      simulation.ref.store %false to %ref : i1, !simulation.ref<i1>
      simulation.return
    }
        // expected-note @+1 {{observer callback is declared here}}
    simulation.func private @observe(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 2 : i64} {
      simulation.call @main(%ctx) : (!simulation.context) -> ()
      %true = arith.constant true
      simulation.return %true : i1
    }

  }
}

// -----

// expected-error @+1 {{snapshot publications must be prepared before scheduling and encoding}}
module attributes {simulation.snapshot_publications, runtime.bytecode_image = array<i8: 0>} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }

  }
}

// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    // expected-error @+1 {{snapshot publications must precede function encoding}}
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, runtime.bytecode_function = 0 : i32} {
      %value = arith.constant true
      simulation.return
    }

  }
}

// -----

// expected-error @+1 {{snapshot publications must be prepared before scheduling and encoding}}
module attributes {simulation.snapshot_publications, runtime.llvm_prepared} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }

  }
}


// -----

// expected-error @+1 {{snapshot publications must be prepared before scheduling and encoding}}
module attributes {simulation.snapshot_publications, runtime.materialized} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }

  }
}


// -----

// expected-error @+1 {{snapshot publications must be prepared before scheduling and encoding}}
module attributes {simulation.snapshot_publications, native.partition_manifests = []} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }

  }
}


// -----

// expected-error @+1 {{snapshot publications must be prepared before scheduling and encoding}}
module attributes {simulation.snapshot_publications, native.physical_partition_manifest = []} {
  simulation.design @invalid {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }

  }
}


// -----

// expected-error @+1 {{snapshot publications must be prepared before scheduling and encoding}}
module attributes {simulation.snapshot_publications} {
  simulation.design @invalid attributes {native.partition_manifest = []} {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = arith.constant true
      simulation.return
    }

  }
}


// -----

module attributes {simulation.snapshot_publications} {
  simulation.design @unclassified {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "top.main"
    simulation.func @main(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      // expected-error @+1 {{snapshot publications require classified memory effects}}
      "opaque.publication"() : () -> ()
      simulation.return
    }
  }
}
