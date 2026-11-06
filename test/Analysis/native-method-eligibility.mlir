// RUN: talos-opt %s --split-input-file --test-talos-replicate --test-talos-native-method-eligibility -o /dev/null 2>&1 | FileCheck %s

// IEEE 1800-2023 13.3/13.4: timing is transitive through task calls.
// Recursive SCCs with no timing can use the native ABI. A bad virtual
// override or caller-unwind effect must exclude every affected caller.
// CHECK: native-method-graph @closures functions=12 families=1 edges=8
module {
  simulation.design @closures {
    simulation.scope.decl 0 hierarchy "top"
    simulation.class.decl @Base id 1 {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.decl @Derived id 2 extends @Base {is_abstract = false, is_final = false, is_interface = false}
    simulation.code_unit.decl 1 in 0 task hierarchy "Base.leaf"
    simulation.class.method @leaf_method of @Base implemented_by @leaf : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 2 in 0 task hierarchy "Base.call_leaf"
    simulation.class.method @call_leaf_method of @Base implemented_by @call_leaf : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 3 in 0 task hierarchy "Base.cycle_a"
    simulation.class.method @cycle_a_method of @Base implemented_by @cycle_a : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 4 in 0 task hierarchy "Base.cycle_b"
    simulation.class.method @cycle_b_method of @Base implemented_by @cycle_b : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 5 in 0 task hierarchy "Base.sleep"
    simulation.class.method @sleep_method of @Base implemented_by @sleep : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 6 in 0 task hierarchy "Base.call_sleep"
    simulation.class.method @call_sleep_method of @Base implemented_by @call_sleep : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 7 in 0 task hierarchy "Base.base_run"
    simulation.class.method @base_run_method of @Base slot 0 signature_id 17 implemented_by @base_run : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.code_unit.decl 8 in 0 task hierarchy "Derived.derived_run"
    simulation.class.method @derived_run_method of @Derived slot 0 signature_id 17 implemented_by @derived_run : (!simulation.context, !simulation.class_handle<@Derived>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.code_unit.decl 9 in 0 task hierarchy "Base.virtual_caller"
    simulation.class.method @virtual_caller_method of @Base implemented_by @virtual_caller : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 10 in 0 function hierarchy "Base.finish"
    simulation.class.method @finish_method of @Base implemented_by @finish : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = false
    }
    simulation.code_unit.decl 11 in 0 task hierarchy "Base.call_finish"
    simulation.class.method @call_finish_method of @Base implemented_by @call_finish : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.code_unit.decl 12 in 0 function hierarchy "Base.pure"
    simulation.class.method @pure_method of @Base implemented_by @pure : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = false
    }
    simulation.func @leaf(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 12 : i32} {
      simulation.return
    }
    simulation.func @call_leaf(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 12 : i32} {
      simulation.task.call @leaf(%ctx, %this) arguments 2 to ^done : !simulation.context, !simulation.class_handle<@Base>
    ^done:
      simulation.return
    }
    simulation.func @cycle_a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 12 : i32} {
      simulation.task.call @cycle_b(%ctx, %this) arguments 2 to ^done : !simulation.context, !simulation.class_handle<@Base>
    ^done:
      simulation.return
    }
    simulation.func @cycle_b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 4 : i64, entry_kind = 12 : i32} {
      simulation.task.call @cycle_a(%ctx, %this) arguments 2 to ^done : !simulation.context, !simulation.class_handle<@Base>
    ^done:
      simulation.return
    }
    simulation.func @sleep(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 5 : i64, entry_kind = 12 : i32} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^done
    ^done:
      simulation.return
    }
    simulation.func @call_sleep(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 6 : i64, entry_kind = 12 : i32} {
      simulation.task.call @sleep(%ctx, %this) arguments 2 to ^done : !simulation.context, !simulation.class_handle<@Base>
    ^done:
      simulation.return
    }
    simulation.func @base_run(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 7 : i64, entry_kind = 12 : i32} {
      simulation.return
    }
    simulation.func @derived_run(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Derived> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 8 : i64, entry_kind = 12 : i32} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^done
    ^done:
      simulation.return
    }
    simulation.func @virtual_caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 9 : i64, entry_kind = 12 : i32} {
      simulation.class.virtual_task_call %this[@base_run_method] slot 0 signature_id 17 () arguments 0 to ^done : (!simulation.class_handle<@Base>) -> ()
    ^done:
      simulation.return
    }
    simulation.func @finish(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 10 : i64, entry_kind = 8 : i32} {
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
    simulation.func @call_finish(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 11 : i64, entry_kind = 12 : i32} {
      simulation.call @finish(%ctx, %this) : (!simulation.context, !simulation.class_handle<@Base>) -> ()
      simulation.return
    }
    simulation.func @pure(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 12 : i64, entry_kind = 8 : i32} {
      simulation.return
    }
  }
}

// CHECK: native-method @leaf_method task=1 eligible=1
// CHECK: native-method @call_leaf_method task=1 eligible=1
// CHECK: native-method @cycle_a_method task=1 eligible=1
// CHECK: native-method @cycle_b_method task=1 eligible=1
// CHECK: native-method @sleep_method task=1 eligible=0
// CHECK: native-method @call_sleep_method task=1 eligible=0
// CHECK: native-method @base_run_method task=1 eligible=1
// CHECK-NEXT: native-family 17 task=1 eligible=0
// CHECK: native-method @derived_run_method task=1 eligible=0
// CHECK-NEXT: native-family 17 task=1 eligible=0
// CHECK: native-method @virtual_caller_method task=1 eligible=0
// CHECK: native-method @finish_method task=0 eligible=0
// CHECK: native-method @call_finish_method task=1 eligible=0
// CHECK: native-method @pure_method task=0 eligible=1

// -----

// No implemented methods: do not scan unrelated function bodies.
// CHECK: native-method-graph @no_methods functions=0 families=0 edges=0
module {
  simulation.design @no_methods {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "unrelated"
    simulation.func @unrelated(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      simulation.return
    }
  }
}

// -----

// One virtual-family node shares the forty caller/override relationships.
// The budget rejects a quadratic caller-times-override expansion.
// CHECK: native-method-graph @shared functions=80 families=1 edges=80
// CHECK: native-method @target39 task=1 eligible=1
// CHECK-NEXT: native-family 17 task=1 eligible=1
// CHECK: native-method @caller39 task=1 eligible=1
module attributes {test.native_method_edge_limit = 100 : i64} {
  simulation.design @shared {
    simulation.scope.decl 0 hierarchy "top"
    simulation.class.decl @"C#" id 1 {is_abstract = false, is_final = false, is_interface = false, test.replicate = 40, test.replicate_stride = {id = 1}}
    simulation.class.method @"target#" of @"C#" slot 0 signature_id 17 implemented_by @"body#" : (!simulation.context, !simulation.class_handle<@"C#">) -> () {is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true, test.replicate = 40}
    simulation.class.method @"caller#" of @"C#" implemented_by @"call#" : (!simulation.context, !simulation.class_handle<@"C#">) -> () {is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false, test.replicate = 40}
    simulation.code_unit.decl 1 in 0 task hierarchy "body#" {test.replicate = 40, test.replicate_stride = {id = 2}}
    simulation.code_unit.decl 2 in 0 task hierarchy "call#" {test.replicate = 40, test.replicate_stride = {id = 2}}
    simulation.func @"body#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@"C#"> {simulation.capture_kind = 1 : i32}) attributes {code_unit_id = 1 : i64, entry_kind = 12 : i32, test.replicate = 40, test.replicate_stride = {code_unit_id = 2}} {
      simulation.return
    }
    simulation.func @"call#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@"C#"> {simulation.capture_kind = 1 : i32}) attributes {code_unit_id = 2 : i64, entry_kind = 12 : i32, test.replicate = 40, test.replicate_stride = {code_unit_id = 2}} {
      simulation.class.virtual_task_call %this[@"target#"] slot 0 signature_id 17 () arguments 0 to ^done : (!simulation.class_handle<@"C#">) -> ()
    ^done:
      simulation.return
    }
  }
}
