// RUN: talos-opt %s --split-input-file --test-talos-replicate --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --implicit-check-not="llvm.call @talos_rt_v1_method_invoke" --implicit-check-not="llvm.call @talos_rt_v1_interface_method_invoke"
// RUN: talos-opt %s --split-input-file --test-talos-replicate --encode-talos-sim-to-bytecode='vpi=off require-bytecode' --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=BYTECODE

// IEEE 1800-2023 8.20/8.26 and 13.5: ordinary slots retain the override;
// interface dispatch chooses the lowest effective slot for its signature.
// A derived class that changes nothing shares its parent's complete table.
// Physical four-state planes and managed values travel directly in the call.
// BYTECODE: module attributes
// BYTECODE-NOT: __talos_native_vtable_
// BYTECODE-NOT: __talos_typed_entry
// CHECK-NOT: @Unused.__talos_typed_entry
// CHECK-LABEL: llvm.func internal @Derived_lowest.__talos_typed_entry(
// CHECK-SAME: -> !llvm.struct<(i9, i9, i64, i32)>
// CHECK: llvm.call @lowest_body
// CHECK-LABEL: llvm.func internal @Derived_method.__talos_typed_entry(
// CHECK: llvm.call @override_body
// CHECK-LABEL: llvm.func internal @Base_method.__talos_typed_entry(
// CHECK: llvm.call @base_body
// CHECK-LABEL: llvm.mlir.global internal constant @Child.__talos_class_descriptor()
// CHECK: llvm.mlir.addressof @[[SHARED:__talos_native_vtable_[0-9]+]]
// CHECK-LABEL: llvm.mlir.global internal constant @Derived.__talos_class_descriptor()
// CHECK: llvm.mlir.addressof @[[SHARED]]
// CHECK-LABEL: llvm.mlir.global internal constant @Base.__talos_class_descriptor()
// CHECK: llvm.mlir.addressof @[[BASE:__talos_native_vtable_[0-9]+]]
// CHECK: llvm.mlir.global internal constant @[[SHARED]]()
// CHECK: llvm.mlir.addressof @Derived_method.__talos_typed_entry
// CHECK: llvm.insertvalue {{.*}}[0]
// CHECK: llvm.mlir.addressof @Derived_lowest.__talos_typed_entry
// CHECK: llvm.insertvalue {{.*}}[1]
// CHECK: llvm.mlir.global internal constant @[[BASE]]()
// CHECK: llvm.mlir.addressof @Base_method.__talos_typed_entry
// CHECK-NOT: __talos_native_vtable_
// CHECK-LABEL: llvm.func @caller(
// CHECK: llvm.icmp "ne" {{.*}} : !llvm.ptr
// CHECK: llvm.cond_br
// CHECK: llvm.getelementptr {{.*}}[0, 21]
// CHECK: llvm.mlir.constant(3 : i32)
// CHECK: llvm.mlir.constant(2 : i32)
// CHECK: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i9, i9, i64) -> !llvm.struct<(i9, i9, i64, i32)>
// CHECK: llvm.call @talos_rt_v1_object_cast
// CHECK: llvm.getelementptr {{.*}}[0, 21]
// CHECK: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i9, i9, i64) -> !llvm.struct<(i9, i9, i64, i32)>
// CHECK-NOT: llvm.call @talos_rt_v1_method_invoke
// CHECK-NOT: llvm.call @talos_rt_v1_interface_method_invoke
// CHECK-NOT: @Unused.__talos_typed_entry
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i16:16-i8:8"} {
  simulation.design @typed {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "base"
    simulation.code_unit.decl 2 in 0 function hierarchy "override"
    simulation.code_unit.decl 3 in 0 function hierarchy "lowest"
    simulation.code_unit.decl 4 in 0 function hierarchy "unused"
    simulation.code_unit.decl 5 in 0 function hierarchy "caller"
    simulation.class.decl @I id 1 {is_abstract = true, is_final = false, is_interface = true}
    simulation.class.decl @J id 2 implements [@I] {is_abstract = true, is_final = false, is_interface = true}
    simulation.class.decl @Derived id 4 extends @Base implements [@J] {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.decl @Child id 5 extends @Derived {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.decl @Base id 3 {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.method @I_method of @I slot 4294967295 signature_id 17 interface_ordinal 0 :
      (!simulation.context, !simulation.class_handle<@I>, !simulation.logic<9>, !simulation.string) -> (!simulation.logic<9>, !simulation.string) {
      is_final = false, is_pure = true, is_static = false, is_task = false, is_virtual = true
    }
    simulation.class.method @Base_method of @Base slot 1000000 signature_id 17 implemented_by @base_body :
      (!simulation.context, !simulation.class_handle<@Base>, !simulation.logic<9>, !simulation.string) -> (!simulation.logic<9>, !simulation.string) {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true
    }
    simulation.class.method @Derived_method of @Derived slot 1000000 signature_id 17 implemented_by @override_body :
      (!simulation.context, !simulation.class_handle<@Derived>, !simulation.logic<9>, !simulation.string) -> (!simulation.logic<9>, !simulation.string) {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true
    }
    simulation.class.method @Derived_lowest of @Derived slot 0 signature_id 17 implemented_by @lowest_body :
      (!simulation.context, !simulation.class_handle<@Derived>, !simulation.logic<9>, !simulation.string) -> (!simulation.logic<9>, !simulation.string) {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true
    }
    simulation.class.method @Unused of @Base slot 99 signature_id 99 implemented_by @unused_body :
      (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true
    }
    simulation.func @base_body(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 1 : i32}, %text: !simulation.string {simulation.capture_kind = 1 : i32}) -> (!simulation.logic<9>, !simulation.string)
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      simulation.return %value, %text : !simulation.logic<9>, !simulation.string
    }
    simulation.func @override_body(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Derived> {simulation.capture_kind = 1 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 1 : i32}, %text: !simulation.string {simulation.capture_kind = 1 : i32}) -> (!simulation.logic<9>, !simulation.string)
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      simulation.return %value, %text : !simulation.logic<9>, !simulation.string
    }
    simulation.func @lowest_body(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Derived> {simulation.capture_kind = 1 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 1 : i32}, %text: !simulation.string {simulation.capture_kind = 1 : i32}) -> (!simulation.logic<9>, !simulation.string)
        attributes {code_unit_id = 3 : i64, entry_kind = 8 : i32} {
      simulation.return %value, %text : !simulation.logic<9>, !simulation.string
    }
    simulation.func @unused_body(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 4 : i64, entry_kind = 8 : i32} {
      simulation.return
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 1 : i32}, %text: !simulation.string {simulation.capture_kind = 1 : i32}) -> !simulation.logic<9>
        attributes {code_unit_id = 5 : i64, entry_kind = 8 : i32} {
      %r:2 = simulation.class.virtual_call %this[@Base_method] slot 1000000 signature_id 17(%value, %text) : (!simulation.class_handle<@Base>, !simulation.logic<9>, !simulation.string) -> (!simulation.logic<9>, !simulation.string)
      %interface = simulation.class.cast %this : !simulation.class_handle<@Base> to !simulation.class_handle<@I>
      %s:2 = simulation.class.virtual_call %interface[@I_method] slot 4294967295 signature_id 17(%value, %text) : (!simulation.class_handle<@I>, !simulation.logic<9>, !simulation.string) -> (!simulation.logic<9>, !simulation.string)
      simulation.return %s#0 : !simulation.logic<9>
    }
    simulation.code_unit.decl 6 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 6 : i64, entry_kind = 0 : i32} {
      simulation.return
    }
  }
}

// -----

// Dense ordinals avoid allocating million-entry tables for sparse slots.
// Seventeen keys require two pointer loads, even with thirty-two-bit pointers.
// BYTECODE: module attributes
// BYTECODE-NOT: __talos_native_vtable_
// BYTECODE-NOT: __talos_typed_entry
// CHECK-LABEL: llvm.func internal @m16.__talos_typed_entry(
// CHECK-SAME: -> !llvm.struct<(i9, i32)>
// CHECK: llvm.call @body
// CHECK-LABEL: llvm.mlir.global internal constant @__talos_native_vtable_34()
// CHECK-SAME: !llvm.array<16 x ptr>
// CHECK: llvm.mlir.addressof @__talos_native_vtable_31
// CHECK: llvm.mlir.addressof @__talos_native_vtable_33
// CHECK-LABEL: llvm.mlir.global internal constant @__talos_native_vtable_33()
// CHECK: llvm.mlir.addressof @m16.__talos_typed_entry
// CHECK-LABEL: llvm.mlir.global internal constant @__talos_native_vtable_31()
// CHECK-NOT: llvm.mlir.global internal constant @__talos_native_vtable_
// CHECK-LABEL: llvm.func @caller16(
// CHECK: llvm.getelementptr {{.*}}[0, 21]
// CHECK: llvm.load {{.*}} {alignment = 4 : i64}
// CHECK: llvm.getelementptr {{.*}}[1] : (!llvm.ptr) -> !llvm.ptr, !llvm.ptr
// CHECK: llvm.load {{.*}} {alignment = 4 : i64}
// CHECK: llvm.getelementptr {{.*}}[0] : (!llvm.ptr) -> !llvm.ptr, !llvm.ptr
// CHECK: llvm.load {{.*}} {alignment = 4 : i64}
// CHECK: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i9) -> !llvm.struct<(i9, i32)>
module attributes {llvm.data_layout = "e-p:32:32-i64:64-i16:16-i8:8", llvm.target_triple = "wasm32-unknown-unknown"} {
  simulation.design @sparse {
    simulation.scope.decl 0 hierarchy "top"
    simulation.class.decl @C id 1 {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.method @"m#" of @C slot 1000000 signature_id 1 implemented_by @body :
      (!simulation.context, !simulation.class_handle<@C>, i9) -> i9 {
      is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = true,
      test.replicate = 17, test.replicate_stride = {slot = 1000000, signature_id = 1}
    }
    simulation.code_unit.decl 1 in 0 function hierarchy "body"
    simulation.func @body(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32}, %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      simulation.return %value : i9
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "caller#" {test.replicate = 17, test.replicate_stride = {id = 1}}
    simulation.func @"caller#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32}, %value: i9 {simulation.capture_kind = 1 : i32}) -> i9
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32, test.replicate = 17, test.replicate_stride = {code_unit_id = 1}} {
      %r = simulation.class.virtual_call %this[@"m#"] slot 1000000 signature_id 1(%value) {test.replicate_stride = {slot = 1000000, signature_id = 1}} : (!simulation.class_handle<@C>, i9) -> i9
      simulation.return %r : i9
    }
    simulation.code_unit.decl 19 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 19 : i64, entry_kind = 0 : i32} {
      simulation.return
    }
  }
}
