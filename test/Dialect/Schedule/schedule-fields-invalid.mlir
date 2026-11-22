// RUN: talos-opt %s --split-input-file --verify-diagnostics

// Typed scheduling fields have their payload and belong on one kind of
// operation: a function's roles, a fixed NBA slot global's field, a module's
// VPI write profile.
module attributes {schedule.eval.writable_vpi} {
  llvm.mlir.global internal @slot() {schedule.nba.slot = #schedule.nba_slot<site = 3, field = unknown>} : i64
  llvm.func @kernel() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel|eval_body>} {
    llvm.return
  }
  func.func @body() attributes {schedule.eval.role = #schedule.eval_role<eval_body>} {
    return
  }
}

// -----
// expected-error @+1 {{attribute 'schedule.eval.role' has the wrong payload kind}}
llvm.func @kernel() attributes {schedule.eval.role = 3 : i32} {
  llvm.return
}

// -----
// expected-error @+1 {{attribute 'schedule.eval.role' belongs on a function}}
llvm.mlir.global internal @kernel() {schedule.eval.role = #schedule.eval_role<eval_body>} : i64

// -----
// expected-error @+1 {{attribute 'schedule.nba.slot' has the wrong payload kind}}
llvm.mlir.global internal @slot() {schedule.nba.slot = 3 : i64} : i64

// -----
// expected-error @+1 {{attribute 'schedule.nba.slot' belongs on an llvm.mlir.global}}
llvm.func @slot() attributes {schedule.nba.slot = #schedule.nba_slot<site = 3, field = value>} {
  llvm.return
}

// -----
// expected-error @+1 {{attribute 'schedule.eval.writable_vpi' has the wrong payload kind}}
module attributes {schedule.eval.writable_vpi = true} {
}

// -----
// expected-error @+1 {{attribute 'schedule.eval.writable_vpi' belongs on a module}}
llvm.func @guard() attributes {schedule.eval.writable_vpi} {
  llvm.return
}
