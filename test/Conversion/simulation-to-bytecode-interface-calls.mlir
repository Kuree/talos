// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' | FileCheck %s
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --test-talos-print-bytecode='metadata=true' -o /dev/null 2>&1 \
// RUN:   | FileCheck %s --check-prefix=PRINT
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --convert-talos-sim-processes-to-llvm-coroutines -o /dev/null

module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @interface_calls {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "Base.get"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.call"
    simulation.code_unit.decl 3 in 0 function hierarchy "Base.skip"

    simulation.class.decl @Empty id 1 {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.decl @Getter id 3 {
      is_abstract = true, is_final = false, is_interface = true
    }
    simulation.class.decl @Base id 2 implements [@Getter] {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.method @Getter_skip of @Getter slot 4294967295
        signature_id 16 interface_ordinal 0 :
      (!simulation.context, !simulation.class_handle<@Getter>) -> i32 {
        is_final = false, is_pure = true, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.class.method @Getter_get of @Getter slot 4294967295
        signature_id 17 interface_ordinal 1 :
      (!simulation.context, !simulation.class_handle<@Getter>) -> i32 {
        is_final = false, is_pure = true, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.class.method @Base_get of @Base slot 0 signature_id 17
        implemented_by @base_get :
      (!simulation.context, !simulation.class_handle<@Base>) -> i32 {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }
    simulation.class.method @Base_skip of @Base slot 1 signature_id 16
        implemented_by @base_skip :
      (!simulation.context, !simulation.class_handle<@Base>) -> i32 {
        is_final = true, is_pure = false, is_static = false,
        is_task = false, is_virtual = true
      }

    simulation.func @base_get(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base>
          {simulation.capture_kind = 1 : i32}) -> i32
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      %value = arith.constant 7 : i32
      simulation.return %value : i32
    }

    simulation.func @base_skip(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base>
          {simulation.capture_kind = 1 : i32}) -> i32
        attributes {code_unit_id = 3 : i64, entry_kind = 8 : i32} {
      %zero = arith.constant 0 : i32
      simulation.return %zero : i32
    }

    simulation.func @call(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %base: !simulation.class_handle<@Base>
          {simulation.capture_kind = 2 : i32},
        %interface: !simulation.class_handle<@Getter>
          {simulation.capture_kind = 2 : i32}) -> i32
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      %class = simulation.class.virtual_call
        %base[@Base_get] slot 0 signature_id 17() :
        (!simulation.class_handle<@Base>) -> i32
      %result = simulation.class.virtual_call
        %interface[@Getter_get] slot 4294967295 signature_id 17() :
        (!simulation.class_handle<@Getter>) -> i32
      simulation.return %result : i32
    }
  }
}

// Class dispatch remains opcode 41 with dense slot 0. Interface dispatch uses
// opcode 56 and indexes operand record 4 containing interface ID 3/ordinal 1;
// neither instruction carries the transitional UINT32_MAX sentinel.
// CHECK: runtime.bytecode_image = array<i8:
// PRINT: operand 4: dst=3 src=1
// PRINT: opcode=41 flags=1 dst=0 src0=1 src1=1 src2=2 aux=3 imm=17
// PRINT: opcode=56 flags=1 dst=4 src0=2 src1=5 src2=2 aux=7 imm=17
