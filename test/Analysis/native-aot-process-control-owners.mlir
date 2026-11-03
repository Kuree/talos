// RUN: talos-opt %s -split-input-file -o /dev/null \
// RUN:   --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),test-talos-native-aot-analysis)' \
// RUN:   2>&1 | FileCheck %s

// IEEE 1800-2023 9.7: a process handle names only a process that executed
// process::self(), also inside a task or a virtual method its body calls, and
// kill() also ends what that process spawned. With process control present,
// the controller and every process a handle can name leave the generated
// plan; an unrelated process keeps its actor slot (two-tier P1e).
// CHECK-LABEL: native-aot eligible=true fully=false
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @unrelated
// CHECK-NOT: actor
// CHECK-DAG: bytecode @controller bb0
// CHECK-DAG: bytecode @direct bb2
// CHECK-DAG: bytecode @via_task bb2
// CHECK-DAG: bytecode @via_method bb2
// CHECK-DAG: bytecode @via_direct bb2
// CHECK-DAG: bytecode @via_chain bb2
// CHECK-DAG: bytecode @outer_note bb0
// CHECK: reason process control is runtime-owned
// CHECK-NEXT: reason process handle source is runtime-owned

module {
  simulation.design @process_control_owners {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "unrelated"
    simulation.code_unit.decl 3 in 0 always hierarchy "direct"
    simulation.code_unit.decl 4 in 0 always hierarchy "via_task"
    simulation.code_unit.decl 5 in 0 always hierarchy "via_method"
    simulation.code_unit.decl 6 in 0 initial hierarchy "controller"
    simulation.code_unit.decl 7 in 0 task hierarchy "note"
    simulation.code_unit.decl 8 in 0 function hierarchy "base_grab"
    simulation.code_unit.decl 9 in 0 function hierarchy "grab"
    simulation.code_unit.decl 10 in 0 fork hierarchy "child"
    simulation.code_unit.decl 11 in 0 always hierarchy "via_direct"
    simulation.code_unit.decl 12 in 0 function hierarchy "direct_grab"
    simulation.code_unit.decl 13 in 0 always hierarchy "via_chain"
    simulation.code_unit.decl 14 in 0 task hierarchy "outer_note"
    simulation.class.decl @Base id 1 {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.decl @Grabber id 2 extends @Base {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.method @Base_grab of @Base slot 0 signature_id 1000 implemented_by @base_grab : (!simulation.context, !simulation.class_handle<@Base>) -> !simulation.process {is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true}
    simulation.class.method @Grabber_grab of @Grabber slot 0 signature_id 1000 implemented_by @grab : (!simulation.context, !simulation.class_handle<@Grabber>) -> !simulation.process {is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true}

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %zero = simulation.logic.constant false, false : !simulation.logic<1>
      %clock = simulation.ref.alloc %zero : !simulation.logic<1> -> !simulation.ref<!simulation.logic<1>>
      %null = simulation.process.null
      %handle = simulation.ref.alloc %null : !simulation.process -> !simulation.ref<!simulation.process>
      %object = simulation.class.null : !simulation.class_handle<@Base>
      %unrelated = simulation.spawn @unrelated(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %direct = simulation.spawn @direct(%ctx, %clock, %handle) : !simulation.context, !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.process> -> !simulation.process
      %via_task = simulation.spawn @via_task(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %via_method = simulation.spawn @via_method(%ctx, %clock, %handle, %object) : !simulation.context, !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.process>, !simulation.class_handle<@Base> -> !simulation.process
      %controller = simulation.spawn @controller(%ctx, %handle) : !simulation.context, !simulation.ref<!simulation.process> -> !simulation.process
      %via_direct = simulation.spawn @via_direct(%ctx, %clock, %handle, %object) : !simulation.context, !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.process>, !simulation.class_handle<@Base> -> !simulation.process
      %via_chain = simulation.spawn @via_chain(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }

    simulation.func private @via_direct(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32},
        %handle: !simulation.ref<!simulation.process> {simulation.capture_kind = 1 : i32},
        %object: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 11 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %self = simulation.class.direct_call @direct_grab %object() : (!simulation.class_handle<@Base>) -> !simulation.process
      simulation.ref.store %self to %handle : !simulation.process, !simulation.ref<!simulation.process>
      cf.br ^wait
    }

    simulation.func private @direct_grab(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}) -> !simulation.process
        attributes {entry_kind = 8 : i32, code_unit_id = 12 : i64} {
      %self = simulation.process.current
      simulation.return %self : !simulation.process
    }

    // Two levels: via_chain -> outer_note -> note.
    simulation.func private @via_chain(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 13 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      simulation.task.call @outer_note(%ctx) arguments 1 to ^wait : !simulation.context
    }

    simulation.func private @outer_note(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 12 : i32, code_unit_id = 14 : i64} {
      simulation.task.call @note(%ctx) arguments 1 to ^done : !simulation.context
    ^done:
      simulation.return
    }

    simulation.func private @unrelated(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      cf.br ^wait
    }

    // Names itself and forks a child that kill() would also end.
    simulation.func private @direct(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32},
        %handle: !simulation.ref<!simulation.process> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %self = simulation.process.current
      simulation.ref.store %self to %handle : !simulation.process, !simulation.ref<!simulation.process>
      %child = simulation.spawn @child(%ctx) : !simulation.context -> !simulation.process
      cf.br ^wait
    }

    simulation.func private @child(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 10 : i64} {
      simulation.return
    }

    simulation.func private @via_task(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      simulation.task.call @note(%ctx) arguments 1 to ^wait : !simulation.context
    }

    simulation.func private @note(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 12 : i32, code_unit_id = 7 : i64} {
      %self = simulation.process.current
      simulation.return
    }

    simulation.func private @via_method(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32},
        %handle: !simulation.ref<!simulation.process> {simulation.capture_kind = 1 : i32},
        %object: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %self = simulation.class.virtual_call %object[@Base_grab] slot 0 signature_id 1000 () : (!simulation.class_handle<@Base>) -> !simulation.process
      simulation.ref.store %self to %handle : !simulation.process, !simulation.ref<!simulation.process>
      cf.br ^wait
    }

    simulation.func private @base_grab(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}) -> !simulation.process
        attributes {entry_kind = 8 : i32, code_unit_id = 8 : i64} {
      %null = simulation.process.null
      simulation.return %null : !simulation.process
    }

    simulation.func private @grab(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Grabber> {simulation.capture_kind = 1 : i32}) -> !simulation.process
        attributes {entry_kind = 8 : i32, code_unit_id = 9 : i64} {
      %self = simulation.process.current
      simulation.return %self : !simulation.process
    }

    simulation.func private @controller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %handle: !simulation.ref<!simulation.process> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %target = simulation.ref.load %handle : !simulation.ref<!simulation.process> -> !simulation.process
      simulation.process.control kill %target to ^done
    ^done:
      simulation.return
    }
  }
}

// -----

// Without process control a handle cannot change any process, so
// process::self() alone keeps its process in the plan (pay for use).
// CHECK-LABEL: native-aot eligible=true fully=true
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @direct
// CHECK-NOT: reason

module {
  simulation.design @handle_without_control {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "direct"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %zero = simulation.logic.constant false, false : !simulation.logic<1>
      %clock = simulation.ref.alloc %zero : !simulation.logic<1> -> !simulation.ref<!simulation.logic<1>>
      %direct = simulation.spawn @direct(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }

    simulation.func private @direct(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %self = simulation.process.current
      cf.br ^wait
    }
  }
}

// -----

// IEEE 1800-2023 24.7: $exit kills every process of its program, so every
// program-owned actor leaves the plan; module processes keep their slots.
// CHECK-LABEL: native-aot eligible=true fully=false
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @dut
// CHECK-NOT: actor
// CHECK: reason program exit is runtime-owned

module {
  simulation.design @program_exit_owners {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "dut"
    simulation.code_unit.decl 3 in 0 initial hierarchy "tb.exiting"
    simulation.code_unit.decl 4 in 0 initial hierarchy "tb.watcher"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %zero = simulation.logic.constant false, false : !simulation.logic<1>
      %clock = simulation.ref.alloc %zero : !simulation.logic<1> -> !simulation.ref<!simulation.logic<1>>
      %dut = simulation.spawn @dut(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %exiting = simulation.spawn @exiting(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %watcher = simulation.spawn @watcher(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }

    simulation.func private @dut(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      cf.br ^wait
    }

    simulation.func private @exiting(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64,
                    schedule.program_owner_id = 7 : i64} {
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      simulation.program.exit %ctx
      simulation.return
    }

    // Never calls $exit itself, but its program's $exit kills it.
    simulation.func private @watcher(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64,
                    schedule.program_owner_id = 7 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      cf.br ^wait
    }
  }
}

// -----

// The runtime links every process spawned during the root initializer to it,
// so a handle to the root (process::self() in a static initializer) can kill
// every static process: a handle source in the root keeps them all
// runtime-owned.
// CHECK-LABEL: native-aot eligible=false fully=false
// CHECK-NOT: actor
// CHECK: reason process control is runtime-owned

module {
  simulation.design @root_handle_source {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "kept"
    simulation.code_unit.decl 3 in 0 initial hierarchy "controller"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %zero = simulation.logic.constant false, false : !simulation.logic<1>
      %clock = simulation.ref.alloc %zero : !simulation.logic<1> -> !simulation.ref<!simulation.logic<1>>
      %self = simulation.process.current
      %handle = simulation.ref.alloc %self : !simulation.process -> !simulation.ref<!simulation.process>
      %kept = simulation.spawn @kept(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %controller = simulation.spawn @controller(%ctx, %handle) : !simulation.context, !simulation.ref<!simulation.process> -> !simulation.process
      simulation.return
    }

    simulation.func private @kept(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      cf.br ^wait
    }

    simulation.func private @controller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %handle: !simulation.ref<!simulation.process> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %target = simulation.ref.load %handle : !simulation.ref<!simulation.process> -> !simulation.process
      simulation.process.control kill %target to ^done
    ^done:
      simulation.return
    }
  }
}

// -----

// A controller inside a called function or task runs in its caller's process
// (13.3, 13.4), so the calling process is the controller.
// CHECK-LABEL: native-aot eligible=true fully=false
// CHECK-NEXT: actor 0 @root
// CHECK-NEXT: actor 1 @bystander
// CHECK-NOT: actor
// CHECK-DAG: bytecode @stop bb0
// CHECK-DAG: bytecode @caller bb2
// CHECK: reason process control is runtime-owned

module {
  simulation.design @called_controller {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "caller"
    simulation.code_unit.decl 3 in 0 function hierarchy "stop"
    simulation.code_unit.decl 4 in 0 always hierarchy "bystander"

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %zero = simulation.logic.constant false, false : !simulation.logic<1>
      %clock = simulation.ref.alloc %zero : !simulation.logic<1> -> !simulation.ref<!simulation.logic<1>>
      %null = simulation.process.null
      %handle = simulation.ref.alloc %null : !simulation.process -> !simulation.ref<!simulation.process>
      %caller = simulation.spawn @caller(%ctx, %clock, %handle) : !simulation.context, !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.process> -> !simulation.process
      %bystander = simulation.spawn @bystander(%ctx, %clock) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }

    simulation.func private @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32},
        %handle: !simulation.ref<!simulation.process> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %target = simulation.ref.load %handle : !simulation.ref<!simulation.process> -> !simulation.process
      simulation.call @stop(%ctx, %target) : (!simulation.context, !simulation.process) -> ()
      cf.br ^wait
    }

    simulation.func private @stop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !simulation.process {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      simulation.process.control kill %target to ^done
    ^done:
      simulation.return
    }

    simulation.func private @bystander(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      cf.br ^wait
    }
  }
}
