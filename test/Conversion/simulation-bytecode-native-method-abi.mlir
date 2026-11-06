// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=THUNK
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off require-bytecode' --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s --check-prefix=BYTECODE

// IEEE 1800-2023 8.6, 8.20 and 13.5. The native ABI stores i9 in two
// bytes and each plane of logic<65> in nine, aligned to 16. Bytecode keeps
// them in limb-sized registers. The compiler must describe both layouts.
module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i65:128-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @native_method_abi {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "C.method"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.call"
    simulation.class.decl @C id 1 {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.method @C_method of @C slot 0 signature_id 17
        implemented_by @method :
      (!simulation.context, !simulation.class_handle<@C>, i9,
       !simulation.logic<65>, !simulation.class_handle<@C>, f32, f64)
      -> (i9, !simulation.logic<65>, !simulation.class_handle<@C>, f32, f64) {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.class.method @C_reference of @C slot 1 signature_id 18
        implemented_by @reference_method :
      (!simulation.context, !simulation.class_handle<@C>, !simulation.ref<i9>)
      -> i9 {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.func @method(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %a: i9 {simulation.capture_kind = 1 : i32},
        %b: !simulation.logic<65> {simulation.capture_kind = 1 : i32},
        %c: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %d: f32 {simulation.capture_kind = 1 : i32},
        %e: f64 {simulation.capture_kind = 1 : i32})
        -> (i9, !simulation.logic<65>, !simulation.class_handle<@C>, f32, f64)
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      simulation.return %a, %b, %c, %d, %e :
        i9, !simulation.logic<65>, !simulation.class_handle<@C>, f32, f64
    }
    simulation.func @call(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %a: i9 {simulation.capture_kind = 1 : i32},
        %b: !simulation.logic<65> {simulation.capture_kind = 1 : i32},
        %c: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %d: f32 {simulation.capture_kind = 1 : i32},
        %e: f64 {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      %r:5 = simulation.class.virtual_call
        %this[@C_method] slot 0 signature_id 17(%a, %b, %c, %d, %e) :
        (!simulation.class_handle<@C>, i9, !simulation.logic<65>,
         !simulation.class_handle<@C>, f32, f64)
        -> (i9, !simulation.logic<65>, !simulation.class_handle<@C>, f32, f64)
      simulation.return
    }
    simulation.code_unit.decl 3 in 0 function hierarchy "C.reference_method"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.call_reference"
    simulation.func @reference_method(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %text: !simulation.ref<i9> {simulation.capture_kind = 1 : i32})
        -> i9
        attributes {code_unit_id = 3 : i64, entry_kind = 8 : i32} {
      %value = simulation.ref.load %text : !simulation.ref<i9> -> i9
      simulation.return %value : i9
    }
    simulation.func @call_reference(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %text: !simulation.ref<i9> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 4 : i64, entry_kind = 8 : i32} {
      %result = simulation.class.virtual_call
        %this[@C_reference] slot 1 signature_id 18(%text) :
        (!simulation.class_handle<@C>, !simulation.ref<i9>) -> i9
      simulation.return
    }
    simulation.code_unit.decl 5 in 0 function hierarchy "C.packed_method"
    simulation.code_unit.decl 6 in 0 function hierarchy "top.call_packed"
    simulation.class.method @C_packed of @C slot 2 signature_id 19
        implemented_by @packed_method :
      (!simulation.context, !simulation.class_handle<@C>,
       !simulation.packed_array<8 : 0 x i1>,
       !simulation.packed_array<64 : 0 x !simulation.logic<1>>)
      -> (!simulation.packed_array<8 : 0 x i1>,
          !simulation.packed_array<64 : 0 x !simulation.logic<1>>) {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.func @packed_method(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %a: !simulation.packed_array<8 : 0 x i1>
            {simulation.capture_kind = 1 : i32},
        %b: !simulation.packed_array<64 : 0 x !simulation.logic<1>>
            {simulation.capture_kind = 1 : i32})
        -> (!simulation.packed_array<8 : 0 x i1>,
            !simulation.packed_array<64 : 0 x !simulation.logic<1>>)
        attributes {code_unit_id = 5 : i64, entry_kind = 8 : i32} {
      simulation.return %a, %b : !simulation.packed_array<8 : 0 x i1>,
        !simulation.packed_array<64 : 0 x !simulation.logic<1>>
    }
    simulation.func @call_packed(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32},
        %a: !simulation.packed_array<8 : 0 x i1>
            {simulation.capture_kind = 1 : i32},
        %b: !simulation.packed_array<64 : 0 x !simulation.logic<1>>
            {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 6 : i64, entry_kind = 8 : i32} {
      %r:2 = simulation.class.virtual_call
        %this[@C_packed] slot 2 signature_id 19(%a, %b) :
        (!simulation.class_handle<@C>, !simulation.packed_array<8 : 0 x i1>,
         !simulation.packed_array<64 : 0 x !simulation.logic<1>>)
        -> (!simulation.packed_array<8 : 0 x i1>,
            !simulation.packed_array<64 : 0 x !simulation.logic<1>>)
      simulation.return
    }
    simulation.code_unit.decl 7 in 0 function hierarchy "top.control_helper"
    simulation.code_unit.decl 8 in 0 function hierarchy "C.controlled_method"
    simulation.code_unit.decl 9 in 0 function hierarchy "top.call_controlled"
    simulation.class.method @C_controlled of @C slot 3 signature_id 20
        implemented_by @controlled_method :
      (!simulation.context, !simulation.class_handle<@C>) -> () {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.func @control_helper(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 7 : i64, entry_kind = 8 : i32} {
      %never = arith.constant false
      cf.cond_br %never, ^recurse, ^kill
    ^recurse:
      simulation.call @controlled_method(%ctx, %this) :
        (!simulation.context, !simulation.class_handle<@C>) -> ()
      cf.br ^kill
    ^kill:
      %current = simulation.process.current
      simulation.process.control kill %current to ^done
    ^done:
      simulation.return
    }
    simulation.func @controlled_method(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 8 : i64, entry_kind = 8 : i32} {
      simulation.call @control_helper(%ctx, %this) :
        (!simulation.context, !simulation.class_handle<@C>) -> ()
      simulation.return
    }
    simulation.func @call_controlled(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 9 : i64, entry_kind = 8 : i32} {
      simulation.class.virtual_call
        %this[@C_controlled] slot 3 signature_id 20() :
        (!simulation.class_handle<@C>) -> ()
      simulation.return
    }
    simulation.code_unit.decl 10 in 0 function hierarchy "C.finishing_method"
    simulation.code_unit.decl 11 in 0 function hierarchy "top.call_finishing"
    simulation.class.method @C_finishing of @C slot 4 signature_id 21
        implemented_by @finishing_method :
      (!simulation.context, !simulation.class_handle<@C>) -> () {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.func @finishing_method(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 10 : i64, entry_kind = 8 : i32} {
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
    simulation.func @call_finishing(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 11 : i64, entry_kind = 8 : i32} {
      simulation.class.virtual_call
        %this[@C_finishing] slot 4 signature_id 21() :
        (!simulation.class_handle<@C>) -> ()
      simulation.return
    }
  }
}

// CHECK: opcode=63 flags=5
// CHECK-NEXT: native method: argument_planes=6 result_planes=6 result_size=80
// CHECK-NEXT: argument plane=0 register=2 byte_offset=0 native_size=2 result_offset=0
// CHECK-NEXT: argument plane=1 register=3 byte_offset=0 native_size=9 result_offset=0
// CHECK-NEXT: argument plane=2 register=3 byte_offset=16 native_size=9 result_offset=0
// CHECK-NEXT: argument plane=3 register=4 byte_offset=0 native_size=8 result_offset=0
// CHECK-NEXT: argument plane=4 register=5 byte_offset=0 native_size=4 result_offset=0
// CHECK-NEXT: argument plane=5 register=6 byte_offset=0 native_size=8 result_offset=0
// CHECK-NEXT: result plane=0 register=7 byte_offset=0 native_size=2 result_offset=0
// CHECK-NEXT: result plane=1 register=8 byte_offset=0 native_size=9 result_offset=16
// CHECK-NEXT: result plane=2 register=8 byte_offset=16 native_size=9 result_offset=32
// CHECK-NEXT: result plane=3 register=9 byte_offset=0 native_size=8 result_offset=48
// CHECK-NEXT: result plane=4 register=10 byte_offset=0 native_size=4 result_offset=56
// CHECK-NEXT: result plane=5 register=11 byte_offset=0 native_size=8 result_offset=64
// Ordinary reference handles need stable-ID conversion; keep their bytecode call.
// CHECK: opcode=41 flags=1 dst=1
// CHECK-NOT: native method:
// Packed SystemVerilog vectors use exactly the same scalar marshal rules.
// CHECK: opcode=63 flags=2
// CHECK-NEXT: native method: argument_planes=3 result_planes=3 result_size=48
// CHECK-NEXT: argument plane=0 register=2 byte_offset=0 native_size=2 result_offset=0
// CHECK-NEXT: argument plane=1 register=3 byte_offset=0 native_size=9 result_offset=0
// CHECK-NEXT: argument plane=2 register=3 byte_offset=16 native_size=9 result_offset=0
// CHECK-NEXT: result plane=0 register=4 byte_offset=0 native_size=2 result_offset=0
// CHECK-NEXT: result plane=1 register=5 byte_offset=0 native_size=9 result_offset=16
// CHECK-NEXT: result plane=2 register=5 byte_offset=16 native_size=9 result_offset=32
// IEEE 1800-2023 13.4(c): process control is legal in functions. A method
// reaching it through a helper (including a recursive call SCC) must keep
// the bytecode unwind behavior.
// CHECK: opcode=41 flags=0 dst=3
// CHECK-NOT: native method:
// Simulation termination must also unwind through bytecode.
// CHECK: opcode=41 flags=0 dst=4
// CHECK-NOT: native method:

// The native thunk checks physical argument count and the result buffer's
// target size before loading any input or writing a result.
// THUNK-LABEL: llvm.func internal @C_method.__talos_native_thunk(
// THUNK: llvm.mlir.constant(6 : i32)
// THUNK: llvm.icmp "eq" %arg4
// THUNK: llvm.mlir.constant(80 : i64)
// THUNK: llvm.icmp "eq" %arg6
// THUNK: llvm.cond_br
// THUNK: llvm.mlir.constant(8 : i32)

// An explicitly bytecode-only build emits no unused native marshal plans.
// BYTECODE-NOT: native method:
// BYTECODE: opcode=41 flags=5
// BYTECODE-NOT: native method:
// BYTECODE: opcode=41 flags=1 dst=1
// BYTECODE-NOT: native method:
// BYTECODE: opcode=41 flags=2
// BYTECODE-NOT: native method:
// BYTECODE: opcode=41 flags=0 dst=3
// BYTECODE-NOT: native method:
// BYTECODE: opcode=41 flags=0 dst=4
// BYTECODE-NOT: native method:
