// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),encode-talos-sim-to-bytecode{prune-native=true vpi=off})' | talos-opt --split-input-file --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s

// A generated eval body (code unit 3) is called only by the native dispatch,
// and a checkpoint resumes its owning actor, so the pruned image omits it.
// Every spawned process (code unit 2) keeps its body as the exact fallback
// executor (IEEE 1800-2023 4.5, 4.6); other non-actor functions (code unit 4)
// stay conservatively.
// CHECK: function 0: id=2
// CHECK-NOT: id=3
// CHECK: function 1: id=4
// CHECK-NOT: id=3

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @eval_body_scope {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "eval_body_scope.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "eval_body_scope.process"
    simulation.code_unit.decl 3 in 0 function hierarchy "process.__talos_eval_body_0" debug "generated native eval body" {internal}
    simulation.code_unit.decl 4 in 0 function hierarchy "eval_body_scope.helper"
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design

    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %storage = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<8>>
      %process = simulation.spawn @process(%ctx, %storage) :
          !simulation.context, !simulation.ref<!simulation.logic<8>>
          -> !simulation.process
      simulation.return
    }

    simulation.func @process(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }

    simulation.func private @process.__talos_eval_body_0(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64,
                    schedule.eval.continuation = 1 : i32} {
      simulation.return
    }

    simulation.func private @helper(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      simulation.return
    }
  }
}

// -----

// A process kept only as a fallback follows what its body references (its
// call of @helper), not the schedule metadata naming its eval body.
// CHECK: function 0: id=2
// CHECK-NOT: id=3
// CHECK: function 1: id=4
// CHECK-NOT: id=3

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @eval_body_scope {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "eval_body_scope.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "eval_body_scope.process"
    simulation.code_unit.decl 3 in 0 function hierarchy "process.__talos_eval_body_0" debug "generated native eval body" {internal}
    simulation.code_unit.decl 4 in 0 function hierarchy "eval_body_scope.helper"
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design

    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %storage = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<8>>
      %process = simulation.spawn @process(%ctx, %storage) :
          !simulation.context, !simulation.ref<!simulation.logic<8>>
          -> !simulation.process
      simulation.return
    }

    simulation.func @process(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64,
                    schedule.eval.body = @process.__talos_eval_body_0} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.call @helper(%ctx) : (!simulation.context) -> ()
      simulation.return
    }

    simulation.func private @process.__talos_eval_body_0(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64,
                    schedule.eval.continuation = 1 : i32} {
      simulation.return
    }

    simulation.func private @helper(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      simulation.return
    }
  }
}

// -----

// A process that a conservatively kept function also reaches (@launcher
// spawns it) follows every reference, as before, its eval body included.
// CHECK: function 0: id=2
// CHECK: function 1: id=3
// CHECK: function 2: id=4
// CHECK: function 3: id=5

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @eval_body_scope {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "eval_body_scope.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "eval_body_scope.process"
    simulation.code_unit.decl 3 in 0 function hierarchy "process.__talos_eval_body_0" debug "generated native eval body" {internal}
    simulation.code_unit.decl 4 in 0 function hierarchy "eval_body_scope.helper"
    simulation.code_unit.decl 5 in 0 function hierarchy "eval_body_scope.launcher"
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design

    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %storage = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<8>>
      %process = simulation.spawn @process(%ctx, %storage) :
          !simulation.context, !simulation.ref<!simulation.logic<8>>
          -> !simulation.process
      simulation.return
    }

    simulation.func @process(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64,
                    schedule.eval.body = @process.__talos_eval_body_0} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.call @helper(%ctx) : (!simulation.context) -> ()
      simulation.return
    }

    simulation.func private @process.__talos_eval_body_0(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64,
                    schedule.eval.continuation = 1 : i32} {
      simulation.return
    }

    simulation.func private @launcher(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %storage = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<8>>
      %process = simulation.spawn @process(%ctx, %storage) :
          !simulation.context, !simulation.ref<!simulation.logic<8>>
          -> !simulation.process
      simulation.return
    }

    simulation.func private @helper(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      simulation.return
    }
  }
}
