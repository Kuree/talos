// RUN: talos-opt %s --split-input-file --verify-diagnostics
// Compiler-only synchronous calls must retain the task dispatch contract.

module {
  simulation.design @function {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "caller"
    simulation.class.decl @Base id 1 {is_abstract = true, is_final = false, is_interface = false}
    simulation.class.method @method of @Base slot 0 signature_id 17 :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> () {
      is_final = false, is_pure = true, is_static = false, is_task = false, is_virtual = true
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %object: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %arg: i9 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      // expected-error @+1 {{requires a virtual task method declaration}}
      schedule.class.synchronous_call %object[@method] slot 0 signature_id 17 (%arg) : !simulation.class_handle<@Base>, i9
      simulation.return
    }
  }
}

// -----

module {
  simulation.design @slot {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "caller"
    simulation.class.decl @Base id 1 {is_abstract = true, is_final = false, is_interface = false}
    simulation.class.method @method of @Base slot 0 signature_id 17 :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> () {
      is_final = false, is_pure = true, is_static = false, is_task = true, is_virtual = true
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %object: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %arg: i9 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      // expected-error @+1 {{must match the declared task slot and signature}}
      schedule.class.synchronous_call %object[@method] slot 1 signature_id 17 (%arg) : !simulation.class_handle<@Base>, i9
      simulation.return
    }
  }
}

// -----

module {
  simulation.design @signature {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "caller"
    simulation.class.decl @Base id 1 {is_abstract = true, is_final = false, is_interface = false}
    simulation.class.method @method of @Base slot 0 signature_id 17 :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> () {
      is_final = false, is_pure = true, is_static = false, is_task = true, is_virtual = true
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %object: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %arg: i9 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      // expected-error @+1 {{must match the declared task slot and signature}}
      schedule.class.synchronous_call %object[@method] slot 0 signature_id 18 (%arg) : !simulation.class_handle<@Base>, i9
      simulation.return
    }
  }
}

// -----

module {
  simulation.design @arguments {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "caller"
    simulation.class.decl @Base id 1 {is_abstract = true, is_final = false, is_interface = false}
    simulation.class.method @method of @Base slot 0 signature_id 17 :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> () {
      is_final = false, is_pure = true, is_static = false, is_task = true, is_virtual = true
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %object: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %arg: i8 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      // expected-error @+1 {{must match the declared task argument types}}
      schedule.class.synchronous_call %object[@method] slot 0 signature_id 17 (%arg) : !simulation.class_handle<@Base>, i8
      simulation.return
    }
  }
}
