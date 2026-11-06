// RUN: talos-opt %s --symbol-dce | FileCheck %s

// A surviving normalized call keeps its exact method declaration, while an
// unreachable declaration/implementation cycle remains dead (8.6/8.20).
module {
  simulation.design @methods {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "C.used"
    simulation.code_unit.decl 2 in 0 function hierarchy "C.unused"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.caller"
    simulation.class.decl @C id 1 {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.method @used_method of @C implemented_by @used :
      (!simulation.context, !simulation.class_handle<@C>) -> () {
        is_final = false, is_pure = false, is_static = false,
        is_task = false, is_virtual = false, sym_visibility = "private"
      }
    simulation.class.method @unused_method of @C implemented_by @unused :
      (!simulation.context, !simulation.class_handle<@C>) -> () {
        is_final = false, is_pure = false, is_static = false,
        is_task = false, is_virtual = false, sym_visibility = "private"
      }
    simulation.func private @used(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                  %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32,
                    simulation.class_method = @used_method} {
      simulation.return
    }
    simulation.func private @unused(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                    %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32,
                    simulation.class_method = @unused_method} {
      simulation.return
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                            %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 8 : i32} {
      simulation.call @used(%ctx, %this) :
        (!simulation.context, !simulation.class_handle<@C>) -> ()
      simulation.return
    }
  }
}

// CHECK: simulation.class.method @used_method
// CHECK-SAME: sym_visibility = "private"
// CHECK-NOT: @unused_method
// CHECK: simulation.func private @used(
// CHECK-SAME: simulation.class_method = @used_method
// CHECK-NOT: @unused
// CHECK: simulation.func @caller(
// CHECK: simulation.call @used
// CHECK-NOT: @unused
