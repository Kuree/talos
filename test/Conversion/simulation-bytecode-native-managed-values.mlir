// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=LLVM

// IEEE 1800-2023 7.4.2, 8.6 and 13.5: value arguments retain their full
// canonical representation; reference arguments retain their exact alias.
!array = !simulation.unpacked_array<0 : 1 x i8>
!managed = !simulation.managed_ref<i16, @C>
!reference = !simulation.argument_ref<i16>
!queue = !simulation.queue<i8, 0>
module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i192:256-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @managed_method_values {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "C.method"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.caller"
    simulation.class.decl @C id 1 {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.method @C_method of @C slot 0 signature_id 17
        implemented_by @method :
      (!simulation.context, !simulation.class_handle<@C>,
       !simulation.string, !array, !managed, !reference, !queue)
      -> (!simulation.string, !array, !managed, !reference, !queue) {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.func @method(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %s: !simulation.string {simulation.capture_kind = 1 : i32},
        %a: !array {simulation.capture_kind = 1 : i32},
        %m: !managed {simulation.capture_kind = 1 : i32},
        %r: !reference {simulation.capture_kind = 1 : i32},
        %q: !queue {simulation.capture_kind = 1 : i32})
        -> (!simulation.string, !array, !managed, !reference, !queue)
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      simulation.return %s, %a, %m, %r, %q :
        !simulation.string, !array, !managed, !reference, !queue
    }
    simulation.func @caller(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %s: !simulation.string {simulation.capture_kind = 1 : i32},
        %a: !array {simulation.capture_kind = 1 : i32},
        %m: !managed {simulation.capture_kind = 1 : i32},
        %r: !reference {simulation.capture_kind = 1 : i32},
        %q: !queue {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      %result:5 = simulation.class.virtual_call
        %this[@C_method] slot 0 signature_id 17(%s, %a, %m, %r, %q) :
        (!simulation.class_handle<@C>, !simulation.string,
         !array, !managed, !reference, !queue)
        -> (!simulation.string, !array, !managed, !reference, !queue)
      simulation.return
    }
  }
}

// CHECK: opcode=63 flags=5
// CHECK-NEXT: native method: argument_planes=6 result_planes=6 result_size=64
// CHECK-NEXT: argument plane=0 register=2 byte_offset=0 native_size=8 result_offset=0
// CHECK-NEXT: argument plane=1 register=3 byte_offset=0 native_size=2 result_offset=0
// CHECK-NEXT: argument plane=2 register=4 byte_offset=0 native_size=8 result_offset=0
// CHECK-NEXT: argument plane=3 register=4 byte_offset=8 native_size=8 result_offset=0
// CHECK-NEXT: argument plane=4 register=5 byte_offset=0 native_size=24 result_offset=0
// CHECK-NEXT: argument plane=5 register=6 byte_offset=0 native_size=8 result_offset=0
// CHECK-NEXT: result plane=0 register=7 byte_offset=0 native_size=8 result_offset=0
// CHECK-NEXT: result plane=1 register=8 byte_offset=0 native_size=2 result_offset=8
// CHECK-NEXT: result plane=2 register=9 byte_offset=0 native_size=8 result_offset=16
// CHECK-NEXT: result plane=3 register=9 byte_offset=8 native_size=8 result_offset=24
// CHECK-NEXT: result plane=4 register=10 byte_offset=0 native_size=24 result_offset=32
// CHECK-NEXT: result plane=5 register=11 byte_offset=0 native_size=8 result_offset=56
// LLVM-LABEL: llvm.func internal @C_method.__talos_native_thunk(
// LLVM: llvm.mlir.constant(6 : i32)
// LLVM: llvm.mlir.constant(64 : i64)
// LLVM: llvm.call @method
