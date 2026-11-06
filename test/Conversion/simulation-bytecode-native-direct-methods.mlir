// RUN: talos-opt %s --symbol-dce --encode-talos-sim-to-bytecode=vpi=off --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=LLVM
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off require-bytecode' --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s --check-prefix=BYTECODE

// IEEE 1800-2023 8.10/8.20: direct and base-qualified calls retain their
// exact implementation even when the receiver has a derived override.
// Static methods have context plus explicit arguments, with no receiver.
module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @direct_methods {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "Base.exact"
    simulation.code_unit.decl 2 in 0 function hierarchy "Derived.exact"
    simulation.code_unit.decl 3 in 0 function hierarchy "Base.ordinary"
    simulation.code_unit.decl 4 in 0 function hierarchy "Base.static_method"
    simulation.code_unit.decl 5 in 0 function hierarchy "Base.unused"
    simulation.code_unit.decl 6 in 0 function hierarchy "top.caller"
    simulation.code_unit.decl 7 in 0 function hierarchy "Base.controlled"
    simulation.code_unit.decl 8 in 0 function hierarchy "top.helper"
    simulation.code_unit.decl 9 in 0 function hierarchy "top.unsafe_caller"
    simulation.class.decl @Base id 1 {
      is_abstract = false, is_final = false, is_interface = false
    }
    simulation.class.decl @Derived id 2 extends @Base {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.method @Base_exact of @Base slot 0 signature_id 17
        implemented_by @base_body :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> i9 {
        is_final = false, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.class.method @Derived_exact of @Derived slot 0 signature_id 17
        implemented_by @derived_body :
      (!simulation.context, !simulation.class_handle<@Derived>, i9) -> i9 {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.class.method @Base_ordinary of @Base implemented_by @ordinary_body :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> i9 {
        is_final = false, is_pure = false, is_static = false,
        is_task = false, is_virtual = false
      }
    simulation.class.method @Base_static of @Base implemented_by @static_body :
      (!simulation.context, i9) -> i9 {
        is_final = false, is_pure = false, is_static = true,
        is_task = false, is_virtual = false
      }
    simulation.class.method @Base_unused of @Base implemented_by @unused_body :
      (!simulation.context, !simulation.class_handle<@Base>, i9) -> i9 {
        is_final = false, is_pure = false, is_static = false,
        is_task = false, is_virtual = false
      }
    simulation.class.method @Base_controlled of @Base implemented_by @controlled :
      (!simulation.context, !simulation.class_handle<@Base>) -> () {
        is_final = false, is_pure = false, is_static = false,
        is_task = false, is_virtual = false
      }
    simulation.func @base_body(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32},
        %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      simulation.return %value : i9
    }
    simulation.func @derived_body(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Derived> {simulation.capture_kind = 1 : i32},
        %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      simulation.return %value : i9
    }
    simulation.func @ordinary_body(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32},
        %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 3 : i64, entry_kind = 8 : i32} {
      simulation.return %value : i9
    }
    simulation.func @static_body(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 4 : i64, entry_kind = 8 : i32} {
      simulation.return %value : i9
    }
    simulation.func @unused_body(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32},
        %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 5 : i64, entry_kind = 8 : i32} {
      simulation.return %value : i9
    }
    simulation.func @caller(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32},
        %value: i9 {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 6 : i64, entry_kind = 8 : i32} {
      %a = simulation.class.direct_call @base_body %this(%value) :
        (!simulation.class_handle<@Base>, i9) -> i9
      // Optimized direct class calls have already become ordinary calls.
      %b = simulation.call @ordinary_body(%ctx, %this, %a) :
        (!simulation.context, !simulation.class_handle<@Base>, i9) -> i9
      %c = simulation.call @static_body(%ctx, %b) :
        (!simulation.context, i9) -> i9
      simulation.return
    }
    simulation.func @controlled(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 7 : i64, entry_kind = 8 : i32} {
      simulation.call @helper(%ctx) : (!simulation.context) -> ()
      simulation.return
    }
    simulation.func @helper(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 8 : i64, entry_kind = 8 : i32} {
      %current = simulation.process.current
      simulation.process.control kill %current to ^done
    ^done:
      simulation.return
    }
    simulation.func @unsafe_caller(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 9 : i64, entry_kind = 8 : i32} {
      simulation.class.direct_call @controlled %this() :
        (!simulation.class_handle<@Base>) -> ()
      simulation.return
    }
  }
}

// CHECK: opcode=65 flags=1 dst=0 src0=1
// CHECK-NEXT: native method: argument_planes=1 result_planes=1 result_size=2
// CHECK: opcode=65 flags=1 dst=2 src0=1
// CHECK-NEXT: native method: argument_planes=1 result_planes=1 result_size=2
// CHECK: opcode=65 flags=1 dst=3 src0=4294967295
// CHECK-NEXT: native method: argument_planes=1 result_planes=1 result_size=2
// A direct method which transitively kills its process stays interpreted.
// CHECK: opcode=31 flags=0 dst=0 src0=6
// CHECK-NOT: opcode=65

// LLVM-DAG: llvm.mlir.global internal constant @Base.__talos_direct_methods()
// LLVM-DAG: !llvm.array<3 x struct<(i32, i32, ptr, ptr)>>
// LLVM-LABEL: llvm.func internal @Base_ordinary.__talos_native_thunk(
// LLVM: llvm.call @ordinary_body
// LLVM-LABEL: llvm.func internal @Base_static.__talos_native_thunk(
// LLVM: llvm.call @static_body
// LLVM-NOT: @Base_unused.__talos_native_thunk
// LLVM-NOT: @Base_controlled.__talos_native_thunk

// BYTECODE-NOT: opcode=65
// BYTECODE-NOT: native method:
